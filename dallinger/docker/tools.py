import os
import shutil
import time

from subprocess import check_output

from dallinger.utils import abspath_from_egg


class DockerComposeWrapper(object):
    """Wrapper around a docker compose local daemon, modeled after HerokuLocalWrapper.

    Provides for verified startup and shutdown, and allows observers to register
    to recieve subprocess output via 'monitor()'.

    Implements a context manager pattern:

        with DockerComposeWrapper(config, output) as docker:
            docker.monitor(my_callback)

    Arg 'output' should implement log(), error() and blather() methods taking
    strings as arguments.
    """

    shell_command = "docker-compose"

    def __init__(self, config, output, tmp_dir, verbose=True, env=None):
        self.config = config
        self.out = output
        self.verbose = verbose
        self.env = env if env is not None else os.environ.copy()
        self.tmp_dir = tmp_dir

    def copy_docker_compse_files(self):
        for filename in ["docker-compose.yml", "Dockerfile.web", "Dockerfile.worker"]:
            path = abspath_from_egg(
                "dallinger", f"dallinger/command_line/docker/{filename}"
            )
            shutil.copy2(path, self.tmp_dir)

    def __enter__(self):
        self.copy_docker_compse_files()
        os.system("docker-compose up --build -d")
        # Wait for postgres to complete initialization
        while b"ready to accept connections" not in check_output(
            ["docker-compose", "logs", "postgresql"]
        ):
            time.sleep(2)
        os.system("docker-compose exec worker dallinger-housekeeper initdb")
        return self

    def __exit__(self, exctype, excinst, exctb):
        os.system("docker-compose down")

    # To build the docker images and upload them to heroku run the following
    # command in self.tmp_dir:
    # heroku container:push --recursive -a ${HEROKU_APP_NAME}
    # To make sure the app has the necessary addons:
    # heroku addons:create -a ${HEROKU_APP_NAME} heroku-postgresql:hobby-dev
    # heroku addons:create -a ${HEROKU_APP_NAME} heroku-redis:hobby-dev
    # To release containers:
    # heroku container:release web worker -a ${HEROKU_APP_NAME}
    # To initialize the database:
    # heroku run dallinger-housekeeper initdb -a $HEROKU_APP_NAME
