###################################################################################################################
# Usage:                                                                                                          #
# 1: Run below command to capture tcp traffic including rest and rpc calls:                                       #
#   tcpdump -nn -s0 -A 'tcp port 5672 or  3000 or 3001 or 3002 or 3004 or 3005 or 3006 or 3007 or 3008  and \     #
#   (((ip[2:2] - ((ip[0]&0xf)<<2)) - ((tcp[12]&0xf0)>>2)) != 0)' >/tmp/dump                                       #
#                                                                                                                 #
# 2: Use this script to analyze captured data and output to txt files.                                            #
#   ./osc.pl -f /tmp/dump                                                                                         #
#                                                                                                                 #
# 3: Convert the output txt file to a png file with below script:                                                 #
#                                                                                                                 #
###################################################################################################################

