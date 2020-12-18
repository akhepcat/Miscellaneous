#!/usr/bin/python3
#
# based off a generic UDP daemon for python, used to log snmp community strings
#
# must run as root, due to the listening port, but it does drop perms if you've installed
#
# $ git clone http://github.com/seveas/python-prctl
# $ cd python-prctl
# $ python setup.py build
# $ sudo python setup.py install
#
# $ sudo setcap cap_net_bind_service=ie snmplog.py
# $ getcap snmplog.py
# snmplog.py = cap_net_bind_service+ei

import socket
import struct
import sys

noprctl=1
try:
    import prctl
except ModuleNotFoundError:
    pass
else:
    noprctl=0


localIP     = "0.0.0.0"
localPort   = 161
bufferSize  = 1024

msgFromServer       = "ERROR"
bytesToSend         = str.encode(msgFromServer)


def drop_privileges(user=None, rundir=None, caps=None):
    import os
    import pwd

    if caps:
        try:
            prctl.securebits.keep_caps=True
            prctl.securebits.no_setuid_fixup=True
            prctl.capbset.limit(*caps)
            prctl.cap_permitted.limit(*caps)
        except PermissionError:
            pass
        else:
            if os.getuid() != 0:
                # We're not root
                raise PermissionError('Run with sudo or as root user')
            if user is None:
                user = os.getenv('SUDO_USER')
                if user is None:
                    raise ValueError('Username not specified')
                if rundir is None:
                    rundir = os.getcwd()
            # Get the uid/gid from the name
            pwnam = pwd.getpwnam(user)
            # Set user's group privileges
            os.setgroups(os.getgrouplist(pwnam.pw_name, pwnam.pw_gid))
            # Try setting the new uid/gid
            os.setgid(pwnam.pw_gid)
            os.setuid(pwnam.pw_uid)
            os.environ['HOME'] = pwnam.pw_dir
            os.chdir(os.path.expanduser(rundir))
            #Ensure a reasonable umask
            old_umask = os.umask(0o22)
        prctl.cap_effective.limit(*caps)

arguments = len(sys.argv) - 1
out = open(sys.argv[1], 'a') if (arguments > 0) else sys.stdout

# Create a datagram socket
UDPServerSocket = socket.socket(family=socket.AF_INET, type=socket.SOCK_DGRAM)

# Bind to address and ip
UDPServerSocket.bind((localIP, localPort))

out.write("# SNMP logger up and listening" + '\n')
out.flush()

if(noprctl > 0) :
    drop_privileges(user='nobody', rundir='/tmp', caps='')
else:
    drop_privileges(user='nobody', rundir='/tmp', caps=[prctl.CAP_NET_BIND_SERVICE])


# Listen for incoming datagrams
while(True):

    bytesAddressPair = UDPServerSocket.recvfrom(bufferSize)

    message = bytesAddressPair[0]
    address = bytesAddressPair[1]

    length = message[6]
    type = str(int(length)) + "s"
    string = struct.unpack_from(type, message, 7)

    clientMsg = "Message from Client{}: community:".format(address)
    clientMsg += str(string)

    out.write(clientMsg + '\n')
    out.flush()

    # Sending a reply to client
    UDPServerSocket.sendto(bytesToSend, address)
