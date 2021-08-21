#!/bin/bash

TARGET=$1
HOME=$(pwd)

if [[ $# -eq 0 ]];then
        echo "[-] Usage: ./automate.sh <TARGET.com>"
        exit 1;
fi

install_tools(){
	# Get findomain
	wget https://github.com/Findomain/Findomain/releases/download/5.0.0/findomain-linux -O findomain && mv findomain /usr/local/bin
       	# Get subfinder
	GO111MODULE=on go get -v github.com/projectdiscovery/subfinder/v2/cmd/subfinder
	# Get amass
	apt install amass
	# Get jq
	apt install jq
	# Get assetfinder
	go get -u github.com/tomnomnom/assetfinder
	# Get massdns
	cd /opt && git clone https://github.com/blechschmidt/massdns.git
	cd massdns && make
	cp /opt/massdns/bin/massdns /usr/bin/massdns
	# Get shuffledns
	GO111MODULE=on go get -v github.com/projectdiscovery/shuffledns/cmd/shuffledns
	# Get dnsgen
	pip3 install dnsgen
	cp /root/go/bin/* /usr/local/bin
}

wrapper_for_files(){
	mkdir recon-files wordlist-making dnsgen-output censys-results
	wget https://raw.githubusercontent.com/Voker2311/recon-scripts/main/combine.py -O wordlist-making
}

censys_api(){
	cd censys-results
	API_KEY="api_key" # Change this
	SECRET="secret_key" # Change this
	curl -s -X POST https://search.censys.io/api/v1/search/certificates -u $API_KEY:$SECRET -d '{"query":"$TARGET"}' | jq .results[] | grep subject_dn | grep -oE "CN=.*" | awk -F\" '{print $1}' | awk -F\= '{print $2}' | grep -v "*" | sort -u | grep -i "$TARGET" > censys-out.txt
	shuffledns -silent -d $TARGET -list censys-out.txt -r /opt/massdns/lists/resolvers.txt > resolved.txt
}

subdomain_discovery(){
	cd recon-files
	findomain --quiet -t "$TARGET" > "findomain.txt"
	subfinder -silent -d "$TARGET" -t 15 -o "subdomains.txt"
	subfinder -silent -d "$TARGET" -t 10 -o "recursive-domains.txt"
	amass enum -d "$TARGET" -passive -o "amass.txt"
	curl -s "https://crt.sh/?q=$TARGET&output=json" | jq .[].name_value | tr '"' ' ' | awk '{gsub(/\\n/,"\n")}1' | awk '{print $1}' | sort -u > crt.txt
	assetfinder "$TARGET" > assets.txt
	cat *.txt | sort -u > discovery.subs
	shuffledns -silent -d $TARGET -list discovery.subs -r /opt/massdns/lists/resolvers.txt > resolved.txt
	echo "[+] Check subdomains in recon-files"
}

bruteforce(){
	# Bruteforcing DNS names
	echo "[*] Bruteforcing DNS, this might take a while"
	echo "[:)] Go grab a coffee"
	cd wordlist-making
	wget https://wordlists-cdn.assetnote.io/data/manual/2m-subdomains.txt
	#wget https://wordlists-cdn.assetnote.io/data/manual/best-dns-wordlist.txt
	echo "[*] Checking the existence of combine.py"
	if [ -f "combine.py" ];then
		echo "[+] Started with 2m subdomains.."
		python combine.py $TARGET "2m-subdomains.txt" > list1.txt
		sleep 5
		#python combine.py $TARGET "best-dns-wordlist.txt" > list2.txt
		cat list1.txt | sort -u > total-subs.txt
		shuffledns -silent -d $TARGET -list total-subs.txt -r /opt/massdns/lists/resolvers.txt > resolved.txt
	else
		echo "[-] File not found"
		exit 1;
	fi
}

dnsgen(){
	cd $HOME/dnsgen-output
	cp $HOME/wordlist-making/resolved.txt 1.txt
	cp $HOME/recon-files/resolved.txt 2.txt
	cp $HOME/censys-results/resolved.txt 3.txt
	cat * | sort -u > final.txt
	dnsgen final.txt > permutations.txt
	resolve_subs
}

resolve_subs(){
	cd $HOME/dnsgen-output
	/opt/massdns/bin/massdns -r /opt/massdns/lists/resolvers.txt -t A -q -o S permutations.txt > dnsgen-resolved.txt
	cp dnsgen-resolved.txt $HOME/subs.txt
}

install_tools
