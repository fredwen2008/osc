#!/usr/bin/env python
import json
import re
import sys
packets=[]
merged=[]
ip_map = {
    '10.66.187.137' : 'keystone',
    '10.66.187.138' : 'network',
    '10.66.187.139' : 'dashboard',
    '10.66.187.140' : 'nova-api',
    '10.66.187.141' : 'nova-conductor',
    '10.66.187.142' : 'nova-scheduler',
    '10.66.187.143' : 'glance-api',
    '10.66.187.144' : 'glance-registry',
    '10.66.187.145' : 'neutron-server',
    '10.66.187.146' : 'db',
    '10.66.187.147' : 'nova-novncproxy',
    '10.66.187.148' : 'nova-consoleauth',
    '10.66.187.149' : 'qpid',
    '10.66.187.133' : 'haproxy',
    '10.66.112.228' : 'compute',
    '10.66.187.134' : 'client'
}
port_map = {
    '3000' : 'keystone-5000',
    '3001' : 'glance-registry-9191',
    '3002' : 'glance-api-9292',
    '3004' : 'nova-api-8774',
    '3005' : 'nova-api-8775',
    '3006' : 'neutron-server-9696',
    '3007' : 'keystone-35357',
    '3008' : 'nova-novncproxy-6080',
    '5672' : 'qpid-5672'
}
def is_request(to):
    port =to.split('.')[-1] 
    for kport,kvalue in port_map.items():
        if ( port==kport):
            return 1;
    return 0;

def translate_ipport(ipport):
    ipport=ipport.replace(' ', '')
    port   = ipport.split('.')[-1]
    tmp=ipport.split('.')
    tmp.pop()
    ip=".".join(tmp)

    ip   = ip_map.get(ip,ip)
    port = port_map.get(port,port)
    if port.isdigit() :
        return ip;    
    return port;

def merge_pkgs(pkgs):
    for i in range(0,len(pkgs)):
        p = pkgs[i];
        if(p.get('merged',0)==1):
            continue
        completed = 0
        for j in range(i+1,len(pkgs)):
            n=pkgs[j]

            if ( n['from']== p['from'] and n['to'] == p['to'] ):

                if (re.search("oslo.message",n['content'])):
                    completed = 1;
                    merged.append(p)
                    break
                else:
                    p['content']= p['content']+ n['content']
                    n['merged'] = 1
            elif ( n['from']== p['to'] and n['to'] == p['from'] ):
                completed = 1;
                merged.append(p)
                break
        if ( completed==0 ):
            merged.append(p)

    
def format_json(inputtext):
    match= re.match("(.*?oslo\.message.{3})(\{.*\})",inputtext,re.DOTALL)
    httpmatch=re.search("HTTP",inputtext)
    json_class = json.JSONDecoder()
    if match:
        head=match.groups()[0]
        json_text=match.groups()[1];
        json_text=json_text.replace("\n","").replace('\r','')

        inputtext=head+"\n"+json.dumps(json_class.raw_decode(json_text),indent=4)
        return inputtext
    elif httpmatch:
        payloadmatch=re.match("(.*?)(\{.*\})",inputtext,re.DOTALL)
        if payloadmatch:
            head=payloadmatch.groups()[0]
            json_text=payloadmatch.groups()[1]
            json_text=json_text.replace("\n","").replace('\r','')
            inputtext=head+json.dumps(json_class.raw_decode(json_text),indent=4)
        return inputtext
    else:
        return ''
        
def format_pkgs(packets):
    for packet in packets:
        packet['is_request']=is_request(packet['to'])
        packet['FROM']=translate_ipport(packet['from'])
        packet['TO']=translate_ipport(packet['to'])
        packet['content']=format_json(packet['content'])
        lines= packet['content'].split('\n')
        if(packet.get('msg-type',0)==0):
            for line in lines:
                rpcmatch=re.match("(.*?oslo\.message.{3})",line,re.DOTALL)
                httpmatch=re.search("HTTP",line)
                if(httpmatch):
                    packet['msg-type']='REST'
                    urlmatch=re.match("(.*?)HTTP",line)
                    if(urlmatch):
                        packet['summary']=urlmatch.groups()[0]
                    break
                elif (rpcmatch):
                    packet['msg-type']='RPC'
                    break
        if(packet.get('msg-type',0)=='RPC'):
            for line in lines:
                rpcuiniqueId=re.search("_unique_id.*?\s*:\s*(\S+)",line)
                if rpcuiniqueId:
                    packet['unique_id']=rpcuiniqueId.groups()[0]
                    break



def load_pkgs(dumpfile):
    
    #line ="00:57:50.572421 IP 10.66.187.138.55281 > 10.66.187.133.5672: Flags [P.], seq 2659789087:2659789139, ack 588382243, win 131, options [nop,nop,TS val 2521697547 ecr 3939207681], length 52"
    file_object = open(dumpfile)
    #lines = file_object.readlines()
    regexp = "IP(.*) > (.*): Flags.*seq (\d+):(\d+).*length (\d+)"
    for line in file_object:
        r = re.search( regexp, line )
        if r:
            groups=r.groups()
            packet={}
            (packet['from'],packet['to'],packet['start'],packet['end'],packet['length'],packet['content'])=(groups[0],groups[1],groups[2],groups[3],int(groups[4]),'')
            if(packets):
                p=packets[-1]
                p['content']=p["content"][len(p["content"])-p['length']-1:len(p["content"])]

            packets.append(packet)
        else:
            if(packets):
                p=packets[-1]
                if(p["content"]):
                    p["content"]=p["content"]+line
                else:
                    p["content"]=line
    if(packets):
        p=packets[-1]
        if(p["content"]):
            #print p['content']
            p['content']=p["content"][len(p["content"])-p['length']-1:len(p["content"])]


def print_pkgs(packets):
    for packet in packets:
        if(packet.get('msg-type',0)=='REST'):
            if(packet['is_request']):
                print "%s -> %s: %s" %(packet["FROM"],packet["TO"],packet.get('summary',''))

            else:
                print "%s -> %s: Resp %s" %(packet["FROM"],packet["TO"],packet.get('summary',''))
        elif(packet.get('msg-type',0)=='RPC'):
            print "%s -> %s: rpc %s" %(packet["FROM"],packet["TO"],packet['unique_id'])
        else:
            pass
            #print 'wrong'
#print sys.argv[1]
load_pkgs(sys.argv[1])


merge_pkgs(packets)
'''
for packet in merged:
    regexp = "ADMIN_PASS"
    r = re.search( regexp, packet['content'])
    if(r):
        print 'merged packet=========:', packet['content']
'''


format_pkgs(merged)
print_pkgs(merged)

