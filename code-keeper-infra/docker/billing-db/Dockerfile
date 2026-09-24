FROM debian:bullseye

RUN apt-get update && \
    apt-get install -y postgresql-13 postgresql-client-13 && \
    rm -rf /var/lib/apt/lists/*

COPY tools/setup_db.sh /usr/local/bin/setup_db.sh

RUN chmod +x /usr/local/bin/setup_db.sh && \
    mkdir -p /var/lib/postgresql/13/main && \
    chown -R postgres:postgres /var/lib/postgresql/13/main


USER postgres

ENTRYPOINT ["/usr/local/bin/setup_db.sh"]