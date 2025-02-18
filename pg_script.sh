#!/bin/bash

# Fonts
T='\033[0;' # Thin
B='\033[1;' # Bold
RF='31m'    # Red
GF='32m'    # Green
YF='33m'    # Yellow
BF='34m'    # Blue
TF='36m'    # Turquoise
CNL='\033[0m' # Cancel

# Configure ports
echo -e "${T}${BF}Configuring ports...${CNL}"
DEFAULT_PORT=5678
PORT=${1:-$DEFAULT_PORT}
PG_PORT=5432

function is_port_available() {
    local port=$1
    if ss -ltn | grep -q :"$port"; then
        return 1
    else
        return 0
    fi
}

# Check and set the first available port
while ! is_port_available "$PORT"; do
    echo -e "Port ${T}${RF}$PORT${CNL} is in use. Trying the next one..."
    ((PORT++))
done
echo -e "Using port: ${T}${GF}$PORT${CNL}\n"

# Host that will be considered remote for the PostgreSQL container
echo -e "${T}${BF}Setting the address from which the database can be accessed remotely...${CNL}\n"
REMOTE_HOST="172.17.0.1"

# Current directory where files will be stored
HOST_DIR=$(pwd)
echo -e "${T}${BF}Files will be saved in the directory: $HOST_DIR${CNL}\n"

# Check if a container with this name exists
CONTAINER_NAME="pg_16"
JAVA_CONTAINER="java_17"
EXISTING_PG_CONTAINER=$(docker ps -a -q -f name=$CONTAINER_NAME)
EXISTING_JAVA_CONTAINER=$(docker ps -a -q -f name=$JAVA_CONTAINER)

# If the container exists, it needs to be removed
if [ -n "$EXISTING_PG_CONTAINER" ]; then
    echo "Container with name $CONTAINER_NAME found, removing it..."
    docker stop $CONTAINER_NAME
    docker rm $CONTAINER_NAME
fi

if [ -n "$EXISTING_JAVA_CONTAINER" ]; then
    echo -e "Container with name $JAVA_CONTAINER found, removing it...\n"
    docker stop $JAVA_CONTAINER
    docker rm $JAVA_CONTAINER
fi

echo
echo -e "${T}${BF}Configuring the database container...${CNL}"
# Pull the PostgreSQL image
echo "Pulling the PostgreSQL image..."
docker pull postgres:16
echo
# Start the PostgreSQL container on the specified port
echo -e "Starting the PostgreSQL container on port ${B}${GF}$PORT${CNL}..."
docker run --name $CONTAINER_NAME -d -p "$PORT":$PG_PORT -e POSTGRES_PASSWORD=mysecretpassword postgres:16

echo "Initializing..."
while ! docker logs "$CONTAINER_NAME" 2>&1 | grep -q "database system is ready to accept connections"; do
    sleep 1
done

# Create the /data/tests directory in the container for mounting files
docker exec $CONTAINER_NAME mkdir -p /data/tests
echo
# Mount files into the PostgreSQL container
echo "Mounting files into the PostgreSQL container..."
docker cp "$HOST_DIR"/db_filling/. $CONTAINER_NAME:data/
docker cp "$HOST_DIR"/tests/. $CONTAINER_NAME:/data/tests/
echo
# Start the Java container with JDK-17 for data generation
echo -e "${T}${BF}Generating data...${CNL}"
docker run -it --name $JAVA_CONTAINER --network=host --shm-size=1g -v "$HOST_DIR":/data openjdk:17-jdk java -jar /data/Datagenerator.jar /data

# Get Docker logs
# shellcheck disable=SC2046
output=$(docker logs $(docker ps -lq))

# Save the number of suppliers and products in variables
suppliersQuantity=$(echo "$output" | grep -oP 'SUPPLIERS_QUANTITY=\K\d+')
productsQuantity=$(echo "$output" | grep -oP 'PRODUCTS_QUANTITY=\K\d+')

# Remove the Java container
echo "Removing the Java container..."
docker rm $JAVA_CONTAINER -f
echo
# After data generation, mount the generated files into the PostgreSQL container
echo "Mounting the generated data into the PostgreSQL container..."
docker cp "$HOST_DIR"/suppliers.csv $CONTAINER_NAME:/data/suppliers.csv
docker cp "$HOST_DIR"/products.csv $CONTAINER_NAME:/data/products.csv

# Configure the admin user and the database
PG_USER='admin'
PG_PSWD='your_secure_password'
DB_NAME='your_database_name'
echo
echo -e "${T}${BF}Configuring the user $PG_USER and the database $DB_NAME...${CNL}"
docker exec $CONTAINER_NAME psql -U postgres -c "CREATE DATABASE $DB_NAME;"
docker exec $CONTAINER_NAME psql -U postgres -c "CREATE USER $PG_USER WITH PASSWORD '$PG_PSWD';"
docker exec $CONTAINER_NAME psql -U postgres -c "ALTER USER $PG_USER WITH SUPERUSER;"
docker exec $CONTAINER_NAME psql -U postgres -c "GRANT ALL PRIVILEGES ON DATABASE $DB_NAME TO $PG_USER;"
echo
# Configure remote access to PostgreSQL
echo -e "${T}${BF}Configuring remote access from one machine...${CNL}"
docker exec $CONTAINER_NAME bash -c "echo 'host all all $REMOTE_HOST/32 md5' >> /var/lib/postgresql/data/pg_hba.conf"
docker exec $CONTAINER_NAME bash -c "echo \"listen_addresses='*'\" >> /var/lib/postgresql/data/postgresql.conf"
docker exec $CONTAINER_NAME psql -U postgres -c "SELECT pg_reload_conf();"

echo "Now you can connect to the DBMS only from the host $REMOTE_HOST with a password or from inside the container"
echo "For Docker, $REMOTE_HOST is the address of your local machine"
echo "Example connection:"
echo "psql -h localhost -p $PORT -U $PG_USER $DB_NAME"
echo "For user '$PG_USER' the password is '$PG_PSWD', for user 'postgres' the password is 'mysecretpassword'."
echo
# Create tables
echo -e "${T}${BF}Populating the database...${CNL}"
echo "Creating tables..."
docker exec $CONTAINER_NAME psql -U $PG_USER -d $DB_NAME -f /data/tables.sql
echo
# Run the SQL script to insert data
echo "Running the SQL script to insert data..."
docker exec $CONTAINER_NAME psql -U $PG_USER -d $DB_NAME -f /data/insertions.sql
echo
# Copy functions
echo "Copying PostgreSQL functions for inserting and retrieving data..."
docker exec $CONTAINER_NAME psql -U $PG_USER -d $DB_NAME -f /data/functions.sql
echo
echo -e "${B}${TF}Preparation complete. Proceeding to tests${CNL}"

# Timer for tests
countdown() {
    local secs=$1
    while [ "$secs" -ge 0 ]; do
        echo -ne "$secs \r"
        sleep 1
        ((secs--))
    done
    echo
}

# Path to save pgbench logs
PGBENCH_LOGS="$HOST_DIR/pgbench.log"

# Initialize pgbench for testing
echo -e "${T}${BF}Testing with pgbench...${CNL}\n"
CLIENTS=50
THREADS=2
TIME=30
SCALE=1
echo -e "The database was created with ${B}${GF}$suppliersQuantity${CNL} suppliers and ${B}${GF}$productsQuantity${CNL} products"
echo "By default, tests will run with the following parameters:"
echo -e "Number of clients simultaneously sending requests to the DB: ${B}${GF}$CLIENTS${CNL}"
echo -e "Number of threads: ${B}${GF}$THREADS${CNL} \033[3m(Not directly related to the number of CPU cores)\033[0m"
echo -e "Duration in seconds: ${B}${GF}$TIME${CNL}"

# Ask if the user wants to change the parameters
echo "In 10 seconds, the default parameters will be applied"
echo "Do you want to change the parameters? (Y / N)"

# Wait for user input for 10 seconds
read -r -t 10 change_params

# If the user does not respond (empty value), continue with the current values
if [[ -z "$change_params" ]]; then
    change_params="n"
    echo "Default values will be used."
fi

# If the user enters 'y', request new parameters
if [[ "${change_params,,}" == "y" ]]; then
    echo "Enter the number of clients. (To keep the default value [$CLIENTS], press ENTER)"
    read -r new_clients
    CLIENTS=${new_clients:-$CLIENTS}  # If no value is entered, keep the default

    echo "Enter the number of threads (default $THREADS):"
    read -r new_threads
    THREADS=${new_threads:-$THREADS}  # If no value is entered, keep the default

    echo "Enter the test duration in seconds (default $TIME):"
    read -r new_time
    TIME=${new_time:-$TIME}  # If no value is entered, keep the default
fi

echo
# After this, continue with the set parameters
echo "Starting tests with the following parameters:"
echo -e "Number of clients: ${B}${GF}$CLIENTS${CNL}"
echo -e "Number of threads: ${B}${GF}$THREADS${CNL}"
echo -e "Duration: ${B}${GF}$TIME${CNL}"
echo
echo -e "${B}${YF}Testing without considering created tables (tables created by pgbench)${CNL}"
echo -e "\033[3;32mPgbench will create three simple tables. By default, the number of records is 100,000.
You will be prompted to scale the number of records (e.g., scale 2 means 200,000 records, 10 means 1,000,000 records, etc.).
Then, for the duration specified above, pgbench will execute queries on these tables with the previously selected number of clients
and threads.
After the test is completed, a report will be presented, from which you can get:
  - The number of transactions actually processed in $TIME seconds (\033[1mnumber of transactions actually processed\033[0m\033[3;32m);
  - The average latency of one transaction (\033[1mlatency average\033[0m\033[3;32m);
  - The number of transactions per second (\033[1mtps\033[0m\033[3;32m);
  and other data.\033[0m"
echo
echo "Run the test?"
echo -e "\033[1;32m'Y'\033[0m to run. Any other key to skip"
read -r execute1
if [[ "${execute1,,}" == "y" ]]; then
    echo -e "Specify the scaling level (e.g., 2). To keep the default value, press ${B}${GF}ENTER${CNL}"
    read -r scale
    SCALE=${scale:-$SCALE}
    echo -e "Running the test...\n"

    echo -e "Pgbench is initializing its tables...\n"
    docker exec $CONTAINER_NAME pgbench -i -s "$SCALE" -U $PG_USER -d $DB_NAME

    echo -e "\nFor $TIME seconds, pgbench will test the database with its tables"
    countdown "$TIME" &
    CDWN_PID=$!
    docker exec $CONTAINER_NAME pgbench -c "$CLIENTS" -j "$THREADS" -T "$TIME" -U $PG_USER $DB_NAME 2>"$PGBENCH_LOGS" | sed -n \
    '/transaction type:/,$p'
else
    echo "Skipping the test"
fi
wait "$CDWN_PID"

echo -e "\n${B}${TF}Testing your created tables...${CNL}\n"

for sql_file in $(docker exec $CONTAINER_NAME ls /data/tests/); do
    echo -e "${B}${YF}Testing $sql_file...${CNL}"
    echo "Run the test?"
    echo -e "\033[1;32m'Y'\033[0m to run, any other key to skip"
    read -r execute
    if [[ "${execute,,}" == "y" ]]; then
        echo "Running the test..."
        countdown "$TIME" &
        CDWN_PID=$!
        docker exec $CONTAINER_NAME pgbench -f "/data/tests/$sql_file" -c "$CLIENTS" -j "$THREADS" -T "$TIME" -U $PG_USER -d $DB_NAME \
        2>"$PGBENCH_LOGS" | sed -n '/transaction type:/,$p'
    else
        echo -e "Skipping the test\n"
    fi
    wait "$CDWN_PID"
done

echo -e "\nAll configurations completed successfully!\n"
echo -e "Pgbench logs are saved in $PGBENCH_LOGS\n"
