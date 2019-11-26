#!/usr/bin/env python3
"""Run script.
"""
import logging
import os
import shlex
import shutil
import subprocess
import sys
from typing import List

logger = logging.getLogger("cli")

APP = "sentiment-analysis"
IMAGE = f"perdy/{APP}"
APP_PATH = f"/srv/apps/{APP}"
LOCAL_PATH = os.path.abspath(os.path.dirname(__file__))


def request_install_requirement(package: str):
    response = None
    while response is None:
        response = input(f"Package {package} is not installed, do you want to install it? [Y|n] ")

        if response in ("N", "n", "no", "No", "NO"):
            logger.error(f"Package {package} is not installed, run 'pip install {package}' to install it")
            sys.exit(1)
        elif response in ("Y", "y", "yes", "Yes", "YES", ""):
            subprocess.run(shlex.split(f"pip install {package}"))
            logger.info(f"Package {package} installed, run me again!")
            sys.exit(0)
        else:
            response = None


try:
    from clinner.command import Type, command
    from clinner.run import Main
except Exception:
    request_install_requirement("clinner")

try:
    import jinja2

    templates = jinja2.Environment(loader=jinja2.FileSystemLoader("."), trim_blocks=True, lstrip_blocks=True)
except Exception:
    request_install_requirement("jinja2")


@command(command_type=Type.PYTHON, parser_opts={"help": "Build docker image"})
def build(*args, **kwargs):
    context = {
        "from_image": "python:3.7-slim",
        "labels": ['maintainer="Perdy <perdy@perdy.io>"'],
        "project": {"name": APP, "files": []},
        "app": {
            "path": APP.replace("-", "_"),
            "packages": {"runtime": ["curl", "unzip", "libhdf5-dev"], "build": ["build-essential"]},
            "requirements": ["requirements.txt", "constraints.txt"],
        },
        "test": {
            "path": "tests",
        },
    }

    dockerfile = templates.get_template("Dockerfile.j2").render(**context)
    logger.debug("---- Dockerfile ----\n%s\n--------------------", dockerfile)
    subprocess.run(shlex.split(f"docker build -t {kwargs['tag']} -f- .") + list(args), input=dockerfile.encode("utf-8"))


@command(command_type=Type.PYTHON, parser_opts={"help": "Clean directory"})
def clean(*args, **kwargs):
    if os.getuid() != 0:
        logger.error("It is necessary to call clean with sudo")
        return None

    for path in (".pytest_cache", ".coverage", "test-results"):
        try:
            if os.path.isfile(path):
                os.remove(path)
            else:
                shutil.rmtree(path)
            logger.info("Removed successfully: %s", path)
        except Exception:
            logger.error("Cannot remove: %s", path)


@command(command_type=Type.SHELL, parser_opts={"help": "Run command through entrypoint"})
def run(*args, **kwargs) -> List[List[str]]:
    return [shlex.split(f"docker run -it --rm -p 8000:8000 -p 8080:8080 -v {LOCAL_PATH}:{APP_PATH} {kwargs['tag']}")]


class Make(Main):
    def add_arguments(self, parser):
        parser.add_argument("-t", "--tag", help="Docker image tag", default=f"{IMAGE}:latest")


if __name__ == "__main__":
    sys.exit(Make().run())
