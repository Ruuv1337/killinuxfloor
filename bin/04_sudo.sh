echo -n 'Installing KF2 service delegation rules... '

# sudo roles
cp -f share/kf2-sudo /etc/sudoers.d/
cp -f share/kf2autokick-sudo /etc/sudoers.d/

# selinux context
restorecon ${RESTORECON_FLAGS} -r /etc/sudoers.d

# file permissions
chmod 0440 /etc/sudoers.d/kf2-sudo
chmod 0440 /etc/sudoers.d/kf2autokick-sudo

${ECHO_DONE}
