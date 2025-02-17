#!/bin/bash

#Цвета
T='\033[0;' # Тонкий
B='\033[1;' # Жирный
RF='31m' # Красный
GF='32m' # Зелёный
YF='33m' # Жёлтый
BF='34m' # Синий
TF='36m' # Бирюзовый
CNL='\033[0m' #Отмена

# Настраиваем порты
echo -e "${T}${BF}Настраиваем порты...${CNL}"
DEFAULT_PORT=5678
PORT=${1:-$DEFAULT_PORT}
PG_PORT=5432

function is_port_available(){
  local port=$1
 if ss -ltn | grep -q :$port; then
   return 1
  else
   return 0
 fi
}

# Проверяем и устанавливаем первый доступный порт
while ! is_port_available $PORT; do
  echo -e "Порт ${T}${RF}$PORT${CNL} используется. Пробуем следующий..."
 ((PORT++))
done
echo -e "Используем порт: ${T}${GF}$PORT${CNL}\n"

# Хост, который будет считаться удаленным для контейнера PostgreSQL
echo -e "${T}${BF}Устанавливаем адрес, с которого можно будет удаленно подключиться к базе данных...${CNL}\n"
REMOTE_HOST="172.17.0.1"

# Текущая директория, где будут храниться файлы
HOST_DIR=$(pwd)
echo -e "${T}${BF}Файлы будут сохранены в директории: $HOST_DIR${CNL}\n"

# Проверяем, существует ли контейнер с таким именем
CONTAINER_NAME="pg_16"
JAVA_CONTAINER="java_17"
EXISTING_PG_CONTAINER=$(docker ps -a -q -f name=$CONTAINER_NAME)
EXISTING_JAVA_CONTAINER=$(docker ps -a -q -f name=$JAVA_CONTAINER)

# Если контейнер существует, то его нужно удалить
if [ ! -z "$EXISTING_PG_CONTAINER" ]; then
  echo "Контейнер с именем $CONTAINER_NAME найден, удаляем его..."
  docker stop $CONTAINER_NAME
  docker rm $CONTAINER_NAME
fi

if [ ! -z "$EXISTING_JAVA_CONTAINER" ]; then
  echo -e "Контейнер с именем $JAVA_CONTAINER найден, удаляем его...\n"
  docker stop $JAVA_CONTAINER
  docker rm $JAVA_CONTAINER
fi
echo
echo -e "${T}${BF}Настройка контейнера с базой данных...${CNL}"
# Загружаем образ PostgreSQL
echo "Загружаем образ PostgreSQL..."
docker pull postgres:16
echo
# Запускаем контейнер PostgreSQL на указанном порту
echo -e "Запускаем контейнер PostgreSQL на порту ${B}${GF}$PORT${CNL}..."
docker run --name $CONTAINER_NAME -d -p $PORT:$PG_PORT -e POSTGRES_PASSWORD=mysecretpassword postgres:16

echo "Инициализация..."
while ! docker logs "$CONTAINER_NAME" 2>&1 | grep -q "database system is ready to accept connections"; do
  sleep 1
done

# Создаем каталог /data/tests в контейнере для монтирования файлов
docker exec $CONTAINER_NAME mkdir -p /data/tests
echo
# Монтируем файлы внутрь контейнера PostgreSQL
echo "Монтируем файлы внутрь контейнера PostgreSQL..."
docker cp $HOST_DIR/db_filling/. $CONTAINER_NAME:data/
docker cp $HOST_DIR/tests/. $CONTAINER_NAME:/data/tests/
echo
# Запускаем контейнер Java с JDK-17 для генерации данных
echo -e "${T}${BF}Генерируем данные...${CNL}"
docker run -it --name $JAVA_CONTAINER --network=host --shm-size=1g -v $HOST_DIR:/data openjdk:17-jdk java -jar /data/Datagenerator.jar /data

# Получаем логи докера
output=$(docker logs $(docker ps -lq))

# Сохраняем в переменные кол-во продавцов и продуктов
suppliersQuantity=$(echo "$output" | grep -oP 'SUPPLIERS_QUANTITY=\K\d+')
productsQuantity=$(echo "$output" | grep -oP 'PRODUCTS_QUANTITY=\K\d+')

# Удаляем контейнер с Java
echo "Удаляем контейнер Java..."
docker rm $JAVA_CONTAINER -f
echo
# После завершения генерации данных, монтируем сгенерированные файлы внутрь контейнера PostgreSQL
echo "Монтируем сгенерированные данные внутрь контейнера PostgreSQL..."
docker cp $HOST_DIR/suppliers.csv $CONTAINER_NAME:/data/suppliers.csv
docker cp $HOST_DIR/products.csv $CONTAINER_NAME:/data/products.csv

# Настроим пользователя admin и базу данных zazitex
PG_USER='admin'
PG_PSWD='your_secure_password'
DB_NAME='your_database_name'
echo
echo -e "${T}${BF}Настроим пользователя $PG_USER и базу данных $DB_NAME...${CNL}"
docker exec $CONTAINER_NAME psql -U postgres -c "CREATE DATABASE $DB_NAME;"
docker exec $CONTAINER_NAME psql -U postgres -c "CREATE USER $PG_USER WITH PASSWORD '$PG_PSWD';"
docker exec $CONTAINER_NAME psql -U postgres -c "ALTER USER $PG_USER WITH SUPERUSER;"
docker exec $CONTAINER_NAME psql -U postgres -c "GRANT ALL PRIVILEGES ON DATABASE $DB_NAME TO $PG_USER;"
echo
# Настроим возможность удаленного подключения к PostgreSQL
echo -e "${T}${BF}Настроим возможность подключения с одной удаленной машины...${CNL}"
docker exec $CONTAINER_NAME bash -c "echo 'host all all $REMOTE_HOST/32 md5' >> /var/lib/postgresql/data/pg_hba.conf"
docker exec $CONTAINER_NAME bash -c "echo \"listen_addresses='*'\" >> /var/lib/postgresql/data/postgresql.conf"
docker exec $CONTAINER_NAME psql -U postgres -c "SELECT pg_reload_conf();"

echo "Сейчас подключиться к СУБД  можно только с хоста $REMOTE_HOST с паролем или изнутри контейнера"
echo "Для Docker $REMOTE_HOST - это адрес вашей локальной машины"
echo "Пример подключения:"
echo "psql -h localhost -p $PORT -U $PG_USER $DB_NAME"
echo "Для пользователя '$PG_USER' пароль '$PG_PSWD', для пользователя 'postgres' пароль 'mysecretpassword'."
echo
# Создаем таблицы
echo -e "${T}${BF}Заполняем базу данных...${CNL}"
echo "Создаем таблицы..."
docker exec $CONTAINER_NAME psql -U $PG_USER -d $DB_NAME -f /data/tables.sql
echo
# Запускаем SQL скрипт для вставки данных
echo "Запускаем SQL скрипт для вставки данных..."
docker exec $CONTAINER_NAME psql -U $PG_USER -d $DB_NAME -f /data/insertions.sql
echo
# Копируем функции
echo "Копируем функции PostgreSQL для вставки и получения данных..."
docker exec $CONTAINER_NAME psql -U $PG_USER -d $DB_NAME -f /data/functions.sql
echo
echo -e "${B}${TF}Подготовка завершена. Переходим к тестам${CNL}"

# Таймер для тестов
countdown() {
  local secs=$1
  while [ $secs -ge 0 ]; do
    echo -ne "$secs \r"
    sleep 1
    ((secs--))
  done
  echo
}


# Путь сохранения логов pgbench
PGBENCH_LOGS="$HOST_DIR/pgbench.log"

# Инициализируем pgbench для тестирования
echo -e "${T}${BF}Тестируем с помощью pgbench...${CNL}\n"
CLIENTS=50
THREADS=2
TIME=30
SCALE=1
echo -e "База данных была создана с ${B}${GF}$suppliersQuantity${CNL} продавцами и ${B}${GF}$productsQuantity${CNL} продуктами"
echo "По умолчанию тесты будут запускаться со следующими параметрами:"
echo -e "Кол-во клиентов, одновременно отправляющих запросы к БД: ${B}${GF}$CLIENTS${CNL}"
echo -e "Количество потоков: ${B}${GF}$THREADS${CNL} \033[3m(Не связано с кол-вом ядер процессора напрямую)\033[0m"
echo -e "Продолжительность в секундах: ${B}${GF}$TIME${CNL}"

# Запрашиваем, хочет ли пользователь изменить параметры
echo "Через 10 секунд будут применены параметры по умолчанию"
echo "Хотите изменить параметры? (Y / N)"

# Ждем ввода пользователя в течение 10 секунд
read -t 10 change_params

# Если пользователь не ответил (пустое значение), продолжаем с текущими значениями
if [[ -z "$change_params" ]]; then
  change_params="n"
  echo "Будут использованы значения по умолчанию."
fi

# Если пользователь ввел 'y', запрашиваем новые параметры
if [[ "${change_params,,}" == "y" ]]; then
  echo "Введите количество клиентов. (Чтобы оставить значение по умолчанию [$CLIENTS], нажмите ENTER)"
  read new_clients
  CLIENTS=${new_clients:-$CLIENTS}  # Если не введено значение, оставляем по умолчанию

  echo "Введите количество потоков (по умолчанию $THREADS):"
  read new_threads
  THREADS=${new_threads:-$THREADS}  # Если не введено значение, оставляем по умолчанию

  echo "Введите продолжительность теста в секундах (по умолчанию $TIME):"
  read new_time
  TIME=${new_time:-$TIME}  # Если не введено значение, оставляем по умолчанию
fi

echo
# После этого можно продолжить с установленными параметрами
echo "Запускаем тесты с параметрами:"
echo -e "Кол-во клиентов: ${B}${GF}$CLIENTS${CNL}"
echo -e "Количество потоков: ${B}${GF}$THREADS${CNL}"
echo -e "Продолжительность: ${B}${GF}$TIME${CNL}"
echo
echo -e "${B}${YF}Тестирование без учёта созданных таблиц (таблицы создаваемые pgbench)${CNL}"
echo -e "\033[3;32mPgbench создаст три простые таблицы. По умолчанию количество записей — 100 000.
Вам будет предложено масштабировать количество записей (например, масштаб 2 означает 200 000 записей, 10 — 1 000 000 записей и т.д.).
Затем в течение времени, указанного вами выше, pgbench будет выполнять запросы к этим таблицам с выбранным ранее количеством клиентов
и потоков.
После завершения теста будет представлен отчёт, из которого можно получить:
  - Количество операций, совершённых за $TIME секунд (\033[1mnumber of transactions actually processed\033[0m\033[3;32m);
  - Среднюю длительность одной операции (\033[1mlatency average\033[0m\033[3;32m);
  - Количество операций в секунду (\033[1mtps\033[0m\033[3;32m);
  и ряд других данных.\033[0m"
echo
echo "Выполнить тест?"
echo -e "\033[1;32m'Y'\033[0m чтобы выполнить. Любая другая клавиша, чтобы пропустить"
read execute1
if [[ "${execute1,,}" == "y" ]]; then
 echo -e "Укажите уровень масштабирования (ex. 2). Чтобы оставить значение по умолчанию, нажмите ${B}${GF}ENTER${CNL}"
 read scale
 SCALE=${scale:-$SCALE}
 echo -e "Выполняем тест...\n"

 echo -e "Pgbench инициализирует свои таблицы...\n"
 docker exec $CONTAINER_NAME pgbench -i -s $SCALE -U $PG_USER -d $DB_NAME

 echo -e "\nВ течение $TIME секунд pgbench будет тестировать базу данных со своими таблицами"
 countdown $TIME &
 CDWN_PID=$!
 docker exec $CONTAINER_NAME pgbench -c $CLIENTS -j $THREADS -T $TIME -U $PG_USER $DB_NAME 2>"$PGBENCH_LOGS" | sed -n \
'/transaction type:/,$p'
else echo "Пропускаем тест"
fi
wait $CDWN_PID


echo -e "${B}Тестирование таблиц созданных вами...${CNL}\n"

for sql_file in $(docker exec $CONTAINER_NAME ls /data/tests/); do
 echo -e "${B}${YF}Тестируем $sql_file...${CNL}"
 echo "Выполнить тест?"
 echo -e "\033[1;32m'Y'\033[0m чтобы выполнить, любая другая клавиша, чтобы пропустить"
 read execute
 if [[ "${execute,,}" == "y" ]]; then
  echo "Выполняем тест..."
  countdown $TIME &
  CDWN_PID=$!
  docker exec $CONTAINER_NAME pgbench -f "/data/tests/$sql_file" -c $CLIENTS -j $THREADS -T $TIME -U $PG_USER -d $DB_NAME \
  2>"$PGBENCH_LOGS" | sed -n '/transaction type:/,$p'
 else echo -e "Пропускаем тест\n"
 fi
 wait $CDWN_PID
done

echo -e "\nВсе настройки выполнены успешно!\n"
echo -e "Логи pgbench сохранены в $PGBENCH_LOGS\n"
