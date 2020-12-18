Requires:
   livecd-tools
Work related to an article posted here:
   Scientific Linux Live CD and DVD http://www.livecd.ethz.ch/build.html
LiveCD rpms obtained from here:
   wget http://www.livecd.ethz.ch/download/RPMS/7x/x86_64/livecd-tools-21.4-5.el7.x86_64.rpm
   wget http://www.livecd.ethz.ch/download/RPMS/7x/x86_64/python-imgcreate-21.4-5.el7.x86_64.rpm
   yum install livecd-tools-21.4-5.el7.x86_64.rpm python-imgcreate-21.4-5.el7.x86_64.rpm
 
Original (reference) kickstart files obtained from here:
   svn co https://svn.iac.ethz.ch/pub/livecd/trunk/SL7/livecd-config livecd-config-SL7


Create the Live image:
   sudo LANG=C livecd-creator --config=$PWD/livecd-costor.ks --fslabel=SL74-CostorLiveCD

Convert to tftpboot directory:
   livecd-iso-to-pxeboot ./livecd-costor-201805232142.iso

Add the following to the "APPEND" line in pxelinux.cfg/default
   inst.sshd=1 console=ttyS0,115200n8

Run dnsmasq:
   dnsmasq -C ./dnsmasq.conf -d -q

