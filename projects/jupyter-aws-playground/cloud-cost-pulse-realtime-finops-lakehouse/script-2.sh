docker compose up -d kafka
until docker compose exec -T kafka /opt/kafka/bin/kafka-topics.sh \
  --bootstrap-server kafka:9092 --list >/dev/null 2>&1; do
  sleep 2
done
docker compose exec -T kafka /opt/kafka/bin/kafka-topics.sh \
  --bootstrap-server kafka:9092 \
  --create --if-not-exists --topic finops-usage --partitions 3 --replication-factor 1
