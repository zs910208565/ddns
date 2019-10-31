#!/bin/bash
Green_font="\033[32m" && Red_font="\033[31m" && Font_suffix="\033[0m"
Info="${Green_font}[Info]${Font_suffix}"
Error="${Red_font}[Error]${Font_suffix}"
echo -e "${Green_font}
#=======================================
# Project: CloudFlare_DDNS_Setter
# Version: 1.0
# Author: nanqinlang
# Blog:   https://sometimesnaive.org
# Github: https://github.com/nanqinlang
#=======================================
# Secondary editing by dovela
# Version: 2.1 beta
# Github: https://github.com/dovela/CloudFlare_DNS_Record
# If you find problems, plz submit issue
#=======================================
${Font_suffix}"

file='/home/CloudFlare_DDNS'
ddns_conf='/home/CloudFlare_DDNS/config.conf'

check_root(){
	[[ "`id -u`" != "0" ]] && echo -e "${Error} must be root user !" && exit 1
}

check_system(){
	[[ -z "`cat /etc/issue | grep -E -i "debian"`" && -z "`cat /etc/issue | grep -E -i "ubuntu"`" && -z "`cat /etc/redhat-release | grep -E -i "CentOS"`" ]] && echo -e "${Error} only support Debian or Ubuntu or CentOS !" && exit 1
}

# 检查dns ip和本机ip是否不同，如果相同则直接退出脚本
check_ip_diff(){
    dns_ip=`ping $domain -c 1 -W 1 | head -n 1 | awk '{print $3}' | sed 's/[()]//g'`
    if [[ $dns_ip == $local_ip ]]; then
        exit 0
    fi
}

check_deps(){
	if  [[ ! -z "`cat /etc/issue | grep -E -i "debian"`" ]]; then
        apt update -y
		apt-get install -y openssl libssl-dev ca-certificates curl python-pip
    elif
		[[ ! -z "`cat /etc/issue | grep -E -i "ubuntu"`" ]]; then
        apt update -y
		apt-get install -y openssl libssl-dev ca-certificates curl python-pip
	elif
		[[ ! -z "`cat /etc/redhat-release | grep -E -i "CentOS"`" ]]; then
        yum install -y epel-release
		yum install -y openssl libssl-dev ca-certificates curl python-pip
	else
		echo -e "${Error} only support Debian or Ubuntu or CentOS !" && exit 1
	fi
}

directory(){
	[[ ! -d ${file} ]] && echo -e "${Error} can not found config directory, please check !" && exit 1
	cd ${file}
}

define(){
	[[ ! -f ${ddns_conf} ]] && echo -e "${Error} can not found config file, please check !" && exit 1

	email=`cat ${ddns_conf} | grep "email" | awk -F "[ =]" '{print $2}'`
	zone_id=`cat ${ddns_conf} | grep "zone_id" | awk -F "[ =]" '{print $2}'`
	api_key=`cat ${ddns_conf} | grep "api_key" | awk -F "[ =]" '{print $2}'`

	record_id=`cat ${ddns_conf} | grep "record_id" | awk -F "[ =]" '{print $2}'`
	domain=`cat ${ddns_conf} | grep "domain" | awk -F "[ =]" '{print $2}'`
	ttl=`cat ${ddns_conf} | grep "ttl" | awk -F "[ =]" '{print $2}'`

    local_ip=`curl ipv4.ip.sb`

    lightsail_switch=`cat ${ddns_conf} | grep "lightsail_switch" | awk -F "[ =]" '{print $2}'`
    lightsail_ipname=`cat ${ddns_conf} | grep "lightsail_ipname" | awk -F "[ =]" '{print $2}'`
    lightsail_instance=`cat ${ddns_conf} | grep "lightsail_instance" | awk -F "[ =]" '{print $2}'`
    check_times=`cat ${ddns_conf} | grep "check_times" | awk -F "[ =]" '{print $2}'`
}

choose_service(){
	if [[ -z "$1" ]]; then
		echo -e "${Info} if you want a automatic ddns, firstly you should get record_id"
		echo -e "${Info} alternatively you can use this script to create a A record and get its id"
		echo -e "${Info} now select required service:\n1.get domain record_id\n2.create a new domain A record\n3.configure lightsail if necessary"
		read -p "(input 1~3 to select):" service
		while [[ ! "${service}" =~ ^[1-3]$ ]]
		do
			echo -e "${Error} invalid input !"
			read -p "(input 1~3 to select):" service
		done
		[[ "${service}" = "1" ]] && get_record_id
        sed -i '/CloudFlare_DDNS/d' /var/spool/cron/root
        echo -e '*/1 * * * * bash CloudFlare_DDNS_Setter.sh --ddns' >> /var/spool/cron/root
		[[ "${service}" = "2" ]] && create_record
        [[ "${service}" = "3" ]] && Lightsail_conf

	elif [[ "$1" == "--ddns" ]]; then
        if [[ $lightsail_switch == "true" ]]; then
            lightsail_change_ip
        fi
        check_ip_diff
		echo -e "${Info} now will start automatically ddns record updating service"
		update_record

	else
		echo -e "${Error} invalid input !" && exit 1
	fi
}

get_record(){
curl -X GET "https://api.cloudflare.com/client/v4/zones/${zone_id}/dns_records?type=A&name${domain}&order=name" \
	 -H "X-Auth-Email: ${email}" \
	 -H "X-Auth-Key: ${api_key}" \
	 -H "Content-Type: application/json"
}

update_record(){
curl -X PUT "https://api.cloudflare.com/client/v4/zones/${zone_id}/dns_records/${record_id}" \
	 -H "X-Auth-Email: ${email}" \
	 -H "X-Auth-Key: ${api_key}" \
	 -H "Content-Type: application/json" \
	 --data '{"type":"A", "name":"'${domain}'", "content":"'${local_ip}'", "ttl":'${ttl}', "proxied":false}'
}

create_record(){
curl -X POST "https://api.cloudflare.com/client/v4/zones/${zone_id}/dns_records" \
	 -H "X-Auth-Email: ${email}" \
	 -H "X-Auth-Key: ${api_key}" \
	 -H "Content-Type: application/json" \
	 --data '{"type":"A", "name":"'${domain}'", "content":"'${local_ip}'", "ttl":'${ttl}', "proxied":false}'
}

get_record_id(){
    records_text=`get_record`
    record_id=`echo -e "${records_text}" | awk -F "\"" '{print $6F}'`
    if [[ ${#record_id} -ne 32 ]]; then
        echo -e "${Error} check if your A record is correct !" && exit 1
    fi
    sed -i '/record_id/d' ${ddns_conf}
    echo -e "record_id=${record_id}" >> ${ddns_conf}
}

Lightsail_conf(){
    pip install awscli --upgrade
    clear
    echo -e '''
   ===============================
    北美: us-east-1 弗吉尼亚州
          us-east-2 俄亥俄州
          us-west-2 俄勒冈州
          ca-central-1 加拿大
    欧洲: eu-west-1 爱尔兰
          eu-west-2 英国
          eu-west-3 法国
          eu-central-1 德国
    亚洲: ap-northeast-1 日本
          ap-northeast-2 韩国
          ap-southeast-1 新加坡
          ap-southeast-2 澳大利亚
          ap-south-1 印度
   ===============================
    '''
    aws configure #输入AWSAccessKeyId和AWSSecretKey以及本机地域,第四项留空，Key由 https://console.aws.amazon.com/iam/home#/security_credential 申请
}

lightsail_change_ip(){
    #检查本机ip是否被tcp阻断
    tcp_status=`curl --silent https://ipcheck.need.sh/api_v2.php?ip=${local_ip} | awk -F '[:}]' '{print $21}'`
    if [[ $tcp_status == "false" ]]; then
        tcp_count=0
        while [[ $tcp_count -lt $check_times ]]
        do
            #如果false则多次检查确认,无true记录的话,更换ip,默认值4次
            tcp_status=`curl --silent https://ipcheck.need.sh/api_v2.php?ip=${local_ip} | awk -F '[:}]' '{print $21}'`
            [[ $tcp_status == "true" ]] && exit 0
            tcp_count=`expr ${tcp_count} + 1`
            sleep 2s
        done
    # 删除现有静态IP
    aws lightsail release-static-ip --static-ip-name ${lightsail_ipname} >/dev/null 2>&1
    # 创建新IP
    aws lightsail allocate-static-ip --static-ip-name ${lightsail_ipname} >/dev/null 2>&1
    # 绑定IP
    aws lightsail attach-static-ip --static-ip-name ${lightsail_ipname} --instance-name ${lightsail_instance} >/dev/null 2>&1
    #待机15s以确保ip更换完毕
    sleep 15s
    fi
}


check_root
check_system
[[ "$1" = "install" ]] && check_deps && exit 0
directory
define
choose_service $1
