# docker build . -t vladmois/airflow-groovy:latest && docker push vladmois/airflow-groovy --all-tags

FROM python:3.9

LABEL maintainer="Vladislav Moiseev <vlad-mois@toloka.ai>"

ENV DEBIAN_FRONTEND=noninteractive \
    TERM=linux

ARG AIRFLOW_VERSION=2.2.4
ARG AIRFLOW_EXTRAS="[celery,microsoft.azure,postgres,redis,slack]"
ARG AIRFLOW_USER_HOME=/usr/local/airflow

ENV AIRFLOW_USER_HOME_DIR=${AIRFLOW_USER_HOME}
ENV AIRFLOW_HOME=${AIRFLOW_USER_HOME}

ENV LANGUAGE=en_US.UTF-8 \
    LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8 \
    LC_CTYPE=en_US.UTF-8 \
    LC_MESSAGES=en_US.UTF-8

RUN useradd -m -s /bin/bash -d ${AIRFLOW_USER_HOME} airflow
RUN export AIRFLOW_UID=$(id -u airflow)

RUN apt-get update && apt-get install -y --no-install-recommends \
        dirmngr \
        fuse \
        gettext-base \
        gnupg \
        less \
        locales \
        nginx \
        openssh-server \
        supervisor \
        tzdata \
        unzip \
        vim \
        wget \
    && sed -i "s/^# en_US.UTF-8 UTF-8$/en_US.UTF-8 UTF-8/g" /etc/locale.gen \
    && locale-gen \
    && update-locale LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 \
    && apt-get clean \
    && apt-get autoclean \
    && rm -rf /var/lib/apt/lists/*

RUN pip install --no-cache-dir --upgrade \
    pip==22.0.4 \
    setuptools==61.1.1 \
    wheel==0.37.1

RUN pip install --no-cache-dir \
    apache-airflow$AIRFLOW_EXTRAS==$AIRFLOW_VERSION \
    azure-storage-blob \
    azure-storage-file-share \
    crowd-kit \
    ipython \
    psycopg2==2.9.3 \
    toloka-kit

RUN mkdir -p /usr/share/man/man1 /usr/share/man/man2
RUN apt-get update && apt-get install -y --no-install-recommends openjdk-11-jre
RUN java --version

ENV JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64
ENV GROOVY_HOME=/opt/groovy
ENV GROOVY_VERSION=4.0.1

RUN set -o errexit -o nounset \
    && echo "Downloading Groovy" \
    && wget --no-verbose --output-document=groovy.zip "https://archive.apache.org/dist/groovy/${GROOVY_VERSION}/distribution/apache-groovy-binary-${GROOVY_VERSION}.zip" \
    \
    && echo "Importing keys listed in http://www.apache.org/dist/groovy/KEYS from key server" \
    && export GNUPGHOME="$(mktemp -d)" \
    && gpg --batch --no-tty --keyserver keyserver.ubuntu.com --recv-keys \
        7FAA0F2206DE228F0DB01AD741321490758AAD6F \
        331224E1D7BE883D16E8A685825C06C827AF6B66 \
        34441E504A937F43EB0DAEF96A65176A0FB1CD0B \
        9A810E3B766E089FFB27C70F11B595CEDC4AEBB5 \
        81CABC23EECA0790E8989B361FF96E10F0E13706 \
    \
    && echo "Checking download signature" \
    && wget --no-verbose --output-document=groovy.zip.asc "https://archive.apache.org/dist/groovy/${GROOVY_VERSION}/distribution/apache-groovy-binary-${GROOVY_VERSION}.zip.asc" \
    && gpg --batch --no-tty --verify groovy.zip.asc groovy.zip \
    && rm --recursive --force "${GNUPGHOME}" \
    && rm groovy.zip.asc \
    \
    && echo "Installing Groovy" \
    && unzip groovy.zip \
    && rm groovy.zip \
    && mv "groovy-${GROOVY_VERSION}" "${GROOVY_HOME}/" \
    && ln --symbolic "${GROOVY_HOME}/bin/grape" /usr/bin/grape \
    && ln --symbolic "${GROOVY_HOME}/bin/groovy" /usr/bin/groovy \
    && ln --symbolic "${GROOVY_HOME}/bin/groovyc" /usr/bin/groovyc \
    && ln --symbolic "${GROOVY_HOME}/bin/groovyConsole" /usr/bin/groovyConsole \
    && ln --symbolic "${GROOVY_HOME}/bin/groovydoc" /usr/bin/groovydoc \
    && ln --symbolic "${GROOVY_HOME}/bin/groovysh" /usr/bin/groovysh \
    && ln --symbolic "${GROOVY_HOME}/bin/java2groovy" /usr/bin/java2groovy \
    \
    && echo "Editing startGroovy to include java.xml.bind module" \
    && sed --in-place 's|startGroovy ( ) {|startGroovy ( ) {\n    JAVA_OPTS="$JAVA_OPTS --add-modules=ALL-SYSTEM"|' "${GROOVY_HOME}/bin/startGroovy"

RUN set -o errexit -o nounset \
    && echo "Testing Groovy installation" \
    && groovy --version

RUN echo "root:Docker!" | chpasswd
COPY sshd_config /etc/ssh/
RUN mkdir -p /tmp
COPY ssh_setup.sh /tmp
RUN chmod +x /tmp/ssh_setup.sh \
    && (sleep 1;/tmp/ssh_setup.sh 2>&1 > /dev/null)

COPY ./nginx.conf /etc/nginx/nginx.conf
COPY ./supervisord.conf /etc/supervisor/conf.d/conf.src.bak

COPY ./run.sh /etc/supervisor/conf.d/run.sh
RUN chmod +x /etc/supervisor/conf.d/run.sh

COPY ./init.sh /etc/supervisor/conf.d/init.sh
RUN chmod +x /etc/supervisor/conf.d/init.sh

COPY ./webserver_config.py ${AIRFLOW_USER_HOME}/webserver_config.py

RUN chown -R airflow: ${AIRFLOW_USER_HOME}

EXPOSE 80 2222

CMD /etc/supervisor/conf.d/run.sh
