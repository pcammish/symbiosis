#
#  Check that email passwords are encrypted.
#
#  If not encrypted, then encrypt
#

# hourly check
@hourly root [ -x /usr/sbin/symbiosis-encrypt-mailpass  ] && /usr/sbin/symbiosis-encrypt-mailpass 

