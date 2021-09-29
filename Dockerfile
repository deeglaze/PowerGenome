FROM ubuntu:16.04

# Note this file assumes extra datasets are in the same directory as this file:
#
# *   pudl_updated.sqlite
# *   v1_resource_groups_data.zip

SHELL [ "/bin/bash", "--login", "-c" ]

# Create a non-root user
ARG username=powergenome-build
ARG uid=1000
ARG gid=100
ENV USER $username
ENV UID $uid
ENV GID $gid
ENV HOME /home/$USER
RUN adduser --disabled-password \
    --gecos "Non-root user" \
    --uid $UID \
    --gid $GID \
    --home $HOME \
    $USER

RUN echo "Installing dependency packages"

RUN apt update && apt -o Acquire::Retries=5 -o Acquire::http::Dl-Limit=800 install -y \
    zip \
    software-properties-common \
    wget
RUN add-apt-repository ppa:deadsnakes/ppa
RUN apt update
RUN apt -o Acquire::Retries=5 -o Acquire::http::Dl-Limit=800 install -y \
    python3.7 \
    python3-pip \
    python3-setuptools
RUN update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.7 1
RUN python3 -m pip install pip
RUN pip3 install --upgrade pip

# Copy over files as root

RUN echo "Initializing file system"

COPY environment.yml requirements.txt /tmp/
RUN chown $UID:$GID /tmp/environment.yml /tmp/requirements.txt

RUN mkdir -p /usr/local/share/datasets/data
COPY data/ /usr/local/share/datasets/data/
RUN chown -R $UID:$GID /usr/local/share/datasets/

COPY v2_1_pudl_powergenome.sqlite /usr/local/share/datasets/pudl_updated.sqlite
RUN chown $UID:$GID /usr/local/share/datasets/pudl_updated.sqlite

COPY v1_resource_groups_data.zip /usr/local/share/datasets/v1_resource_groups_data.zip
RUN chown $UID:$GID /usr/local/share/datasets/v1_resource_groups_data.zip

COPY docker/entrypoint.sh /usr/local/bin/entrypoint.sh
COPY docker/updateCpi.py /usr/local/bin/updateCpi.py
RUN chown $UID:$GID /usr/local/bin/entrypoint.sh \
    /usr/local/bin/updateCpi.py && \
    chmod u+x /usr/local/bin/entrypoint.sh \
    	  /usr/local/bin/updateCpi.py

RUN mkdir -p $HOME && chown $UID:$GID $HOME

COPY setup.py $HOME/setup.py
COPY powergenome/ $HOME/powergenome/
RUN chown -R $UID:$GID $HOME/setup.py $HOME/powergenome/

### Switch to non-root and setup build environment.

USER $USER

RUN unzip /usr/local/share/datasets/v1_resource_groups_data.zip -d /usr/local/share/datasets

RUN echo "Installing miniconda"

# install miniconda
ENV MINICONDA_VERSION 4.8.2
ENV CONDA_DIR $HOME/miniconda3
RUN wget https://repo.anaconda.com/miniconda/Miniconda3-py37_$MINICONDA_VERSION-Linux-x86_64.sh -O /tmp/miniconda.sh && \
  echo "957d2f0f0701c3d1335e3b39f235d197837ad69a944fa6f5d8ad2c686b69df3b /tmp/miniconda.sh" | sha256sum --check --status


RUN chmod +x /tmp/miniconda.sh
RUN /tmp/miniconda.sh -b -p $CONDA_DIR && \
    rm /tmp/miniconda.sh
# make non-activate conda commands available
ENV PATH=$CONDA_DIR/bin:$PATH
# make conda activate command available from /bin/bash --login shells
RUN echo ". $CONDA_DIR/etc/profile.d/conda.sh" >> ~/.profile
# make conda activate command available from /bin/bash --interative shells
RUN conda init bash

### Project directory

# create a project directory inside user home
ENV PROJECT_DIR $HOME/PowerGenome
RUN mkdir $PROJECT_DIR
WORKDIR $PROJECT_DIR

### Conda Env

RUN echo "Building conda environment"

# build the conda environment
ENV ENV_PREFIX $PROJECT_DIR/powergenome
RUN conda update --name base --channel defaults conda && \
    conda env create --prefix $ENV_PREFIX --file /tmp/environment.yml --force && \
    conda clean --all --yes

RUN echo "Running postBuild"

# TODO(dionnaglaze): Find out why pandas didn't install.
RUN pip3 install pandas requests

# run the postBuild script to install any JupyterLab extensions
RUN conda activate $ENV_PREFIX
RUN pushd $HOME && pip3 install -e . && popd
RUN /usr/local/bin/updateCpi.py
RUN conda deactivate

# Set the entrypoint for creating the right environment to run PowerGenome

ENTRYPOINT [ "/usr/local/bin/entrypoint.sh" ]


