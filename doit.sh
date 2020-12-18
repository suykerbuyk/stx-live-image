#$!/bin/sh
if [ -d tftpboot ] ; then
	rm -rf tftpboot
fi
livecd-creator -d -c stx-prvsnr.ks -f "stx-prvsnr" --title="stx-prvsnr" --product="hermi"  $@ && \
livecd-iso-to-pxeboot ./stx-prvsnr.iso && \
rm -rf *.iso
