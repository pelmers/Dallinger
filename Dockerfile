# syntax = docker/dockerfile:1.2
###################### Image with build tools to compile wheels ###############
FROM python:3.11-bullseye as wheels
ENV DEBIAN_FRONTEND=noninteractive

LABEL Description="Dallinger base docker image" Version="1.0"

EXPOSE 5000

# Install build dependencies
RUN apt-get update && \
    apt-get install -y libpq-dev python3-pip python3-dev tzdata pandoc && \
    python3 -m pip install -U pip && \
    rm -rf /var/lib/apt/lists/*

COPY constraints.txt requirements.txt /dallinger/
WORKDIR /dallinger

RUN --mount=type=cache,target=/root/.cache/pip \
    mkdir /wheelhouse && \
    python3 -m pip wheel --wheel-dir=/wheelhouse -r requirements.txt -c constraints.txt


###################### Dallinger base image ###################################
FROM python:3.11-bullseye as dallinger
ENV DEBIAN_FRONTEND=noninteractive
LABEL org.opencontainers.image.source https://github.com/Dallinger/Dallinger

# Install runtime dependencies
RUN apt-get update && \
    apt-get install -y libpq5 python3-pip busybox tzdata --no-install-recommends && \
    busybox --install && \
    python3 -m pip install -U pip && \
    rm -rf /var/lib/apt/lists/*

COPY constraints.txt requirements.txt /dallinger/
WORKDIR /dallinger

RUN --mount=type=bind,source=/wheelhouse,from=wheels,target=/wheelhouse \
    (ls -l /wheelhouse || (echo 'You need to enable docker buildkit to build dallinger: DOCKER_BUILDKIT=1' && false) ) &&\
    python3 -m pip install --find-links file:///wheelhouse -r requirements.txt -c constraints.txt

COPY . /dallinger
RUN python3 -m pip install --find-links file:///wheelhouse -e .[data,docker]

# Add two ENV variables as a fix when using python3, to prevent this error:
# Click will abort further execution because Python 3 was configured
# to use ASCII as encoding for the environment.
# Consult http://click.pocoo.org/python3/for mitigation steps.
ENV LC_ALL C.UTF-8
ENV LANG C.UTF-8

ENV SKIP_DEPENDENCY_CHECK true

# Also install docker client package (docker-ce-cli) to support using the dallinger image without installing dallinger:
# some dallinger commands depend on the docker binaries being available (the dallinger commands will invoke docker on
# bahalf of the user). So they need to be availble in the same context dallinger is run, i.e. inside a container.

RUN apt-get update && \
    apt-get install -y ca-certificates curl gnupg && \
    mkdir -p /etc/apt/keyrings && \
    curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg && \
    echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian \
    bullseye stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null && \
    apt-get update && \
    apt-get install -y docker-ce-cli && \
    rm -rf /var/lib/apt/lists/*


CMD /bin/bash

###################### Dallinger bot image ####################################
FROM dallinger as dallinger-bot
ENV DEBIAN_FRONTEND=noninteractive
LABEL org.opencontainers.image.source https://github.com/Dallinger/Dallinger

RUN --mount=type=cache,target=/chromedownload \
    apt update && \
    `# We install busybox to be able to use wget and later unzip, and to minimize image size` \
    apt install -y busybox && \
    ([ -f /chromedownload/google-chrome-stable_current_amd64.deb ] || busybox wget https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb -O /chromedownload/google-chrome-stable_current_amd64.deb) &&  \
    apt install -y --no-install-recommends /chromedownload/google-chrome-stable_current_amd64.deb && \
    rm -rf /var/lib/apt/lists/*

RUN OUR_CHROME_VERSION=$(google-chrome --version |sed "s/Google Chrome //;s/ //;s/\.[^.]*$//") && \
    echo Finding the chromedriver version to install for chrome $OUR_CHROME_VERSION && \
    CHROMEDRIVER_VERSION=$(busybox wget -O - https://chromedriver.storage.googleapis.com/LATEST_RELEASE_${OUR_CHROME_VERSION}) && \
    echo Installing chromedriver $CHROMEDRIVER_VERSION && \
    busybox wget https://chromedriver.storage.googleapis.com/${CHROMEDRIVER_VERSION}/chromedriver_linux64.zip -O /tmp/chromedriver_linux64.zip && \
    busybox unzip /tmp/chromedriver_linux64.zip -d /usr/local/bin/ && \
    rm /tmp/chromedriver_linux64.zip
