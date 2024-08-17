FROM mongodb/atlas:v1.25.0

RUN yum install -y mongodb-database-tools

COPY startatlas.sh /usr/startatlas.sh

RUN chmod +x /usr/startatlas.sh

CMD /usr/startatlas.sh
