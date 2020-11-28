FROM archlinux:latest

RUN pacman -Sy \
  && pacman --noconfirm -S openssh rdiff-backup \
  && mkdir -p /root/.ssh
RUN echo 'PermitRootLogin yes' >> /etc/ssh/sshd_config
RUN ssh-keygen -A
ADD authorized_keys /root/.ssh
CMD ["/usr/bin/sshd","-D"]
