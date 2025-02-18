# PostgreSQL Performance Testing with Docker

This mini-project provides a set of scripts and utilities for creating a PostgreSQL database, populating it with test data, and running performance tests using `pgbench`.

## Contents

- SQL scripts for creating a database with products and suppliers
- A Java-based utility for populating tables with data
- SQL scripts for testing database queries
- A Bash script (`pg_script.sh`) for partial automation of the testing process

## Technologies Used

- **Docker**
- **PostgreSQL 16**
- **Java 17**

## System Requirements

- **Linux OS** (Developed and tested on Ubuntu 24.04)
- **Docker Installed**

## Quick Start

Navigate to the directory containing `pg_script.sh` and run the following command:

./pg_script.sh

### Port Configuration

The PostgreSQL database inside the Docker container will be exposed on a local machine port, mapped to container port `5432`.

- To specify a port, run:
  
  ./pg_script.sh <port_number>
  
  Example:
  ./pg_script.sh 1234

- If the specified port is in use, the script increments the port number by 1 (e.g., 1235, then 1236, etc.) until it finds an available port.
- If no port is specified, the script starts checking from `5678`.

## Process Overview

1. **Pull Docker Images** (if not already downloaded):
   - PostgreSQL 16
   - OpenJDK 17
   
2. **Container Management:**
   - If a previous `pg_16` container exists, it is stopped and removed.
   - A new PostgreSQL container (`pg_16`) is started.

3. **Database Initialization:**
   - A PostgreSQL database is created.
   - A user `admin` is created with necessary privileges.
   - Remote access from the host machine is enabled.
   
4. **Schema and Data Population:**
   - SQL scripts from `db_filling/` are executed to create tables, indexes, and functions.
   - A Java-based data generator (`Datagenerator.jar`) is executed inside a Docker container to populate the database.
   - Users can specify the number of records (default: `1000` suppliers, `100,000` products).

5. **Performance Testing with `pgbench`**:
   - The user is prompted to configure:
     - Number of clients
     - Number of threads
     - Test duration (seconds)
   - Initial tests are run on tables created by `pgbench`.
   - Additional tests are run on SQL scripts from the `tests/` directory.
   - After each test, key metrics (`TPS`, `Latency Average`) are displayed.
   - Full logs are saved to `pgbench.log` in the working directory.

## Connecting to the Database

After successful execution, connect to the database using:

psql -h localhost -p <port> -U admin your_database_name

- Default PostgreSQL credentials inside the container:
  - `admin` user password: **your_secure_password**
  - `postgres` user password: **mysecretpassword**

## Logs and Results

- Test results and performance logs are stored in `pgbench.log`.
- The script provides summary results for each test run.

## Notes

- If you wish to modify the test scripts, edit the `.sql` files in the `tests/` directory.
- Ensure Docker is installed and running before executing `pg_script.sh`.
- To clean up, manually remove Docker containers:

  docker stop pg_16 java_17
  docker rm pg_16 java_17
