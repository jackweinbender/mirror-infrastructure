FROM git.weinbender.io/labs/ci-base:main

COPY ansible/requirements.txt /tmp/ansible-requirements.txt
RUN pip install --break-system-packages --no-cache-dir -r /tmp/ansible-requirements.txt \
    && rm /tmp/ansible-requirements.txt

COPY ansible/ansible-requirements.yaml /tmp/ansible-galaxy-requirements.yaml
RUN ansible-galaxy collection install -r /tmp/ansible-galaxy-requirements.yaml \
    && rm /tmp/ansible-galaxy-requirements.yaml

WORKDIR /workspace

CMD ["bash"]

