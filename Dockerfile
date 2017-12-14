# ---
# build_root: .
# include:
#  - '*'
# ---

FROM   ubuntu:16.04

# ---------------- #
#   Installation   #
# ---------------- #

# Install all prerequisites
RUN     apt-get update && apt-get -y install nginx supervisor git python-pip libffi-dev libcairo2-dev autoconf libtool check curl npm nodejs-legacy gunicorn &&\
	rm -rf /var/lib/apt/lists/*
RUN npm install -g wizzy &&\
    npm cache clean --force
RUN pip install futures --no-cache-dir

# Checkout the master branches of Graphite, Carbon and Whisper and install from there
RUN     mkdir /src                                                                                                   &&\
        git clone --depth=1 --branch master https://github.com/graphite-project/whisper.git /src/whisper             &&\
        cd /src/whisper                                                                                              &&\
        pip install . --no-cache-dir                                                                                 &&\
        python setup.py install

RUN cd /tmp &&\
    curl -Lo go-carbon.deb https://github.com/lomik/go-carbon/releases/download/v0.11.0/go-carbon_0.11.0_amd64.deb &&\
    dpkg -i go-carbon.deb

RUN     git clone --depth=1 --branch master https://github.com/graphite-project/graphite-web.git /src/graphite-web   &&\
        cd /src/graphite-web                                                                                         &&\
        pip install . --no-cache-dir                                                                                 &&\
        python setup.py install                                                                                      &&\
        pip install -r requirements.txt --no-cache-dir                                                               &&\
        python check-dependencies.py

RUN git clone --depth=1 --branch master https://github.com/statsite/statsite /src/statsite &&\
    cd /src/statsite &&\
    ./autogen.sh &&\
    ./configure && \
    make &&\
    make install

# Install Grafana
RUN     mkdir /src/grafana                                                                                           &&\
        mkdir /opt/grafana                                                                                           &&\
        curl https://s3-us-west-2.amazonaws.com/grafana-releases/release/grafana-4.6.1.linux-x64.tar.gz \
             -o /src/grafana.tar.gz                                                                                  &&\
        tar -xzf /src/grafana.tar.gz -C /opt/grafana --strip-components=1                                            &&\
        rm /src/grafana.tar.gz

# Install carbon-c-relay
RUN git clone https://github.com/grobian/carbon-c-relay /src/carbon-c-relay &&\
  cd /src/carbon-c-relay &&\
  ./configure &&\
  make

# Cleanup Compile Dependencies
RUN     apt-get purge -y git gcc python-dev libffi-dev


# ----------------- #
#   Configuration   #
# ----------------- #

# Configure statsite
COPY     ./statsite/statsite.conf /src/statsite/statsite.conf

# Configure Whisper, Carbon and Graphite-Web
COPY     ./graphite/initial_data.json /opt/graphite/webapp/graphite/initial_data.json
COPY     ./graphite/local_settings.py /opt/graphite/webapp/graphite/local_settings.py
COPY     ./graphite/carbon.conf /opt/graphite/conf/carbon.conf
COPY     ./graphite/storage-schemas.conf /opt/graphite/conf/storage-schemas.conf
COPY     ./graphite/storage-aggregation.conf /opt/graphite/conf/storage-aggregation.conf
RUN     mkdir -p /opt/graphite/storage/whisper                                                                       &&\
        touch /opt/graphite/storage/graphite.db /opt/graphite/storage/index                                          &&\
        chown -R www-data /opt/graphite/storage                                                                           &&\
        chmod 0775 /opt/graphite/storage /opt/graphite/storage/whisper                                               &&\
        chmod 0664 /opt/graphite/storage/graphite.db                                                                 &&\
        cp /src/graphite-web/webapp/manage.py /opt/graphite/webapp                                                   &&\
        cd /opt/graphite/webapp/ && python manage.py migrate --run-syncdb --noinput

# Configure Grafana and wizzy
COPY     ./grafana/custom.ini /opt/grafana/conf/custom.ini
RUN     cd /src                                                                                                      &&\
        wizzy init                                                                                                   &&\
        extract() { cat /opt/grafana/conf/custom.ini | grep $1 | awk '{print $NF}'; }                                &&\
        wizzy set grafana url $(extract ";protocol")://$(extract ";domain"):$(extract ";http_port")                  &&\
        wizzy set grafana username $(extract ";admin_user")                                                          &&\
        wizzy set grafana password $(extract ";admin_password")

# Configure carbon-c-relay
COPY     ./carbon-c-relay/carbon-c-relay.conf /etc/carbon-c-relay/carbon-c-relay.conf

# Add the default datasource and dashboards
RUN 	mkdir /src/datasources                                                                                       &&\
        mkdir /src/dashboards
COPY     ./grafana/datasources/* /src/datasources
COPY     ./grafana/dashboards/* /src/dashboards/
COPY     ./grafana/export-datasources-and-dashboards.sh /src/

# Configure nginx and supervisord
COPY     ./nginx/nginx.conf /etc/nginx/nginx.conf
COPY     ./supervisord.conf /etc/supervisor/conf.d/supervisord.conf

COPY go-carbon/go-carbon.conf /etc/go-carbon/go-carbon.conf


# ---------------- #
#   Expose Ports   #
# ---------------- #

# Grafana
EXPOSE  80

# statsite UDP port
EXPOSE  8125/udp

# statsite Management port
EXPOSE  8126

# Graphite web port
EXPOSE 81

# Graphite Carbon port
EXPOSE 2003

# -------- #
#   Run!   #
# -------- #

CMD     ["/usr/bin/supervisord", "--nodaemon", "--configuration", "/etc/supervisor/conf.d/supervisord.conf"]
