#!/bin/bash

version="1.2.2"
author="Vanduir Santana"

# ------------------------------------------------------------------------------------
#                        ..:: V A R I A V E I S  ::..
# ------------------------------------------------------------------------------------

bipt=""
bdns=""
bdhcp=""

DIRET="/root/dev/rede"
FREDE="$DIRET/etc/rede.csv"
FZONA1="$DIRET/db.c.net"
FZONA2="$DIRET/db.172.16"
FZONA1_H="$DIRET/etc/heads/db.c.net.head"
FZONA2_H="$DIRET/etc/heads/db.172.16.head"
FDHCP_H="$DIRET/etc/heads/dhcpd.conf.head"
FDHCP="dhcpd.conf"
DOMINIO="c.net"
DOMINIOB="c.net."	    # dominio com . no final para inserir nos arqs de conf do bind

LAN="eth0"  	    	# interface interna
#LAN="eth0:1"  	    	# interface interna (lab Active Directory)
#WAN="eth1"	         	# interface externa
WAN="wlan0"	         	# interface externa
MASK=16
IPSRV="172.16.4.20"
CAPTIVEIP=$IPSRV
CAPTIVEPORTA=8081
MARCA_PROXY="1"
MARCA_LIBERADO="2"
MARCA_LIBERADO_CP="3"
verde='\e[32m'
amarelo='\e[93m'
magenta='\e[35m'
azul='\e[34m'
branco='\e[97m'
res='\E[0m'
TDNS="$magenta[ DNS  ]$res"
TDHCP="$amarelo[ DHCP ]$res"
TFW="$verde[ IPT  ]$res"

STATUS_BLOQUEADO="0"    # bloqueado o acesso a internet
STATUS_PROXY="1"        # liberado pra navegar usando o proxy
STATUS_LIBERADO="2"     # totalmente liberado
STATUS_LOGIN_CP=3       # redireciona porta 80 pra porta do app web mac-visitante pra fazer login
STATUS_LIBERADO_CP=4    # apos cadastro do visitante eh liberado acesso

# Verifica se existe arquivo de conf.
if [[ ! -f $FREDE ]]
then
  echo "Nao encontrou arquivo rede.csv"
  exit 0
fi
# ------------------------------------------------------------------------------------
#                         ..::  F  U  N Ç Õ E S ::..
# ------------------------------------------------------------------------------------
# Exibe linha
# -----------------------------------------------------
function elinha() {
  echo -e "$branco-----------------------------------------------------------------------------------------$res"
}

# -----------------------------------------------------
# Cabecalho saida
# -----------------------------------------------------
function cabecalho_s() {
  # imprime cabelho na saida (tela)
  elinha
  echo -e "\e[42m                                  $branco dbIT Tecnologia                                       $res"
}


# -----------------------------------------------------
# Cabeca db.c.net
# -----------------------------------------------------
function dns_cabeca() {
  [[ -f $FZONA1 ]] && rm $FZONA1
  cat $FZONA1_H >> $FZONA1
  # cabeca db.172.16 
  [[ -f $FZONA2 ]] && rm $FZONA2
  cat $FZONA2_H >> $FZONA2
}

# -----------------------------------------------------
# Cabeca dhcp
# -----------------------------------------------------
function dhcp_cabeca() {
  [[ -f $FDHCP ]] && rm $FDHCP
  cat $FDHCP_H >> $FDHCP
}

# -----------------------------------------------------
# Texto do loop
# -----------------------------------------------------
function loop_s() {
  elinha
  echo -e "LOOP ARQUIVO DE CONFIGS DE REDE..."
  elinha
}
# -----------------------------------------------------
# Faz backup antes de mover arquivo
# -----------------------------------------------------
function mv2() {
  local fmod="$1"
  local forig="$2"
  local fbkp="$forig.bkp"
  echo "Backup $forig para $fbkp"
  mv "$forig" "$fbkp"
  echo "Mover $fmod para $forig"
  mv "$fmod" "$forig"
}

# -----------------------------------------------------
# Incrementa serial arquivo de dns
# -----------------------------------------------------
function dns_inc_serial() {
  # pega numero serial do arquivo de zona
  local arq="$1"
  local linha=$(grep "; Serial" $arq) 		# procura linha com o texto "; Serial"
  local serial=$(echo -e "$linha" | xargs)	# retira espacos
  # IFS na msma linha (evitar mudar IFS global)
  IFS=";" read serial nome <<< "$serial"	# separa campos e retorna so serial
  serial=$(echo "$serial" | xargs) 
  local prox=$((serial+1)) 			# proximo serial 

  local linhan=${linha/$serial/$prox}
  sed -i s/"$linha"/"$linhan"/g "$arq"   	# substitui linha no arquivo

  elinha
  echo -e "$TDNS Incrementar serial de $serial para $prox em $arq"
  #echo "$TDNS Linha: $(grep "; Serial" $arq)"
 }

# -----------------------------------------------------
# Insere registro nos arquivos de configuracao
# Arquivos de zonas do bind, dhcpd.conf, etc
# -----------------------------------------------------
function reg() {
  local mac=$1
  local ip=$2
  local nome=$3
  local desc=$4
  local status=$5

  if [[ $bdns ]]; then
    echo -e "$TDNS Inserir host $nome na zona local de clientes: $FZONA1"
    # nome.domino		IN	A	172.16.0.x
    echo -e "$nome.$DOMINIOB\t\tIN\tA\t$ip" >> "$FZONA1"

    echo -e "$TDNS Inserir host $nome na zona local reversa: $FZONA2"
    # evitar mecher no IFS (mas e possivel fazer com IFS e ; td na msma linha: impl. em mseriald )
    # pega dois ultimos octetos do ip
    p3=$(echo $ip | cut -d \. -f 3)
    p4=$(echo $ip | cut -d \. -f 4)
    # XX.XX	IN	PTR	nome.dominio.		; IP
    echo -e "$p4.$p3\tIN\tPTR\t$nome.$DOMINIOB\t\t; $ip" >> "$FZONA2"
  fi
  
  if [[ $bdhcp ]]; then 
    echo -e "$TDHCP Inserir host $nome no dhcp.conf"
    echo "" >> "$FDHCP"
    echo "# $desc" >> "$FDHCP"
    echo "host $nome {" >> "$FDHCP"
    echo "  hardware ethernet $mac;" >> "$FDHCP"
    if [[ "$status" != $STATUS_LIBERADO_CP ]]
    then
      echo "  fixed-address $nome.$DOMINIO;"  >> "$FDHCP"  
    else
      echo "  fixed-address $ip;"  >> "$FDHCP"  
    fi
    echo "}" >> "$FDHCP"
  fi
}

# -----------------------------------------------------
# Inicializar iptables
# -----------------------------------------------------
function ipt_init() {
  elinha
  echo -e "$TFW Iniciando firewall..."
  echo -e "$TFW Limpando regras..."
  iptables -F
  iptables -X
  iptables -t nat -F
  iptables -t nat -X
  iptables -t mangle -F
  iptables -t mangle -X

  iptables -P INPUT ACCEPT
  iptables -P FORWARD ACCEPT
  iptables -P OUTPUT ACCEPT

  echo -e "$TFW Permitir DNS lookups..."
  iptables -A OUTPUT -p udp --dport 53 -j ACCEPT
  #echo -e "$TFW Regras INPUT..."
  #iptables -A INPUT -i lo -j ACCEPT
  #iptables -A INPUT -i $LAN -s 172.16.0.0/$MASK -j ACCEPT
  #iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
}  

## -----------------------------------------------------
## Retorna ultimo octeto do IP pra usar como marca
## pro Captive Portal
## -----------------------------------------------------
#function get_marca_ip() {
#  local ip=$1 
#  # pega ultimo octeto IP
#  MARCA_IP="${ip##*.}"
#}

# -----------------------------------------------------
# Marca pacote pra permitir conexao no ipt_masq ou
# deixa sem marca pra nao navegar
# Permite ou bloqueia ip para navegacao na intenet
# Quando bloquear, libera uaitube.com basico 
# -----------------------------------------------------
function ipt_marcar() {
  local mac=$1
  local ip=$2
  local nome=$3
  local desc=$4
  local status=$5
  local marca=$MARCA_PROXY
  local comentario="REDE  marcado pra liberar por MAC"
  local captive=false

  if [[ "$status" == $STATUS_BLOQUEADO ]] ; then
      echo -e "$TFW BLOQUEAR internet para << $nome >> $ip, $mac"
  elif [[ "$status" == $STATUS_PROXY ]] ; then
      marca=$MARCA_PROXY
      #iptables -t nat -A PREROUTING -i $LAN -m mac --mac-source $mac -j MARK --set-mark $marca

      echo -e "$TFW Proxy nao transparente << $nome >> $ip, $mac"
      # Redireciona quem nao tem proxy configurado pra pagina especifica
      iptables -t nat -A PREROUTING -p tcp -i $LAN -s $ip --dport 80 -j DNAT --to $IPSRV:81
      # Bloqueia portas 80 e 443 pra forçar o usuário a configurar proxy
      iptables -A FORWARD -p tcp -i $LAN -s $ip -m multiport --dports 80,443 -j DROP
      iptables -A FORWARD -p udp -i $LAN -s $ip --dport 443 -j DROP
  else
    if [[ "$status" == $STATUS_LIBERADO ]] ; then
        marca=$MARCA_LIBERADO
    elif [[ "$status" == $STATUS_LOGIN_CP ]] ; then
        comentario="REDE redir. porta 80 pro Captive Portal pra fzr login" 
        captive=true
    elif [[ "$status" == $STATUS_LIBERADO_CP ]] ; then
        comentario="REDE marcado pra liberar pelo Captive Portal" 
        marca=$MARCA_LIBERADO_CP
    fi

    if [ "$captive" = false ]; then
        echo -e "$TFW Marcar pacotes pra << $nome >> $ip, $mac"
        iptables -t nat -A PREROUTING -i $LAN -m mac --mac-source $mac -m comment --comment "$comentario" -j MARK --set-mark $marca

        # Evita nat (redir p site-captive.com dos bloqueados)
        iptables -t nat -A PREROUTING -i $LAN -p tcp -s $ip -m mac --mac-source $mac --dport 80 -j ACCEPT
        # Libera FORWARD de qualquer porta (estudar possibilidade de bloquear algumas portas)
        iptables -A FORWARD -i $LAN -s $ip -m mac --mac-source $mac -j ACCEPT
    else
        echo -e "$TFW Redirecionar a porta 80 para o portal captive-example.com" 
        iptables -t nat -I PREROUTING -i $LAN -p tcp -s $ip -m mac --mac-source $mac --dport 80 -m comment --comment "$comentario" -j DNAT --to $CAPTIVEIP:$CAPTIVEPORTA
        echo -e "$TFW Bloquear trafego na rede para bloqueados..."
        iptables -I FORWARD -p tcp -i $LAN -s $ip -j DROP
        iptables -I FORWARD -p udp -i $LAN -s $ip -j DROP
    fi
  fi
}


# -----------------------------------------------------
# Mascara estacoes q tiverem com os pacotes marcados 
# pela funcao ipt_marcar para que possam navegar 
# na internet
# -----------------------------------------------------
function ipt_masq() {
  elinha
  local comentario="REDE liberado pelo Captive Portal por marca"
  echo -e "$TFW MASQUERADE para quem tiver marcado no PREROUTING por MAC" 
  #iptables -t nat -A POSTROUTING -o $WAN -m mark --mark $MARCA_PROXY -j MASQUERADE
  iptables -t nat -A POSTROUTING -o $WAN -m mark --mark $MARCA_LIBERADO -j MASQUERADE
  iptables -t nat -A POSTROUTING -o $WAN -m mark --mark $MARCA_LIBERADO_CP -m comment --comment "$comentario" -j MASQUERADE
}

# -----------------------------------------------------
# Redireciona todo o restante para o portal 
# site-captive.com para usarem gratuitamente 
# Depois bloqueia todo trafego para FORWARD
# -----------------------------------------------------
function ipt_redir() {
  elinha 
  echo -e "$TFW Redirecionar a porta 80 dos bloqueados para o portal site-captive.com" 
  #iptables -t nat -A PREROUTING -i $LAN -p tcp -s 0/0 --dport 80 -j DNAT --to $CAPTIVEIP:$CAPTIVEPORTA
  iptables -t nat -A PREROUTING -i $LAN -p tcp -s 0/0 --dport 80 -j DNAT --to $IPSRV:80

  echo -e "$TFW Bloquear trafego na rede para status != liberado ou liberado_cb..."
  iptables -A FORWARD -p tcp -i $LAN -s 0/0 -j DROP
  iptables -A FORWARD -p udp -i $LAN -s 0/0 -j DROP
}

# -----------------------------------------------------
# Uso do comando
# -----------------------------------------------------
function uso() {
  cabecalho_s
  elinha
  echo "dbIT REDE uso: Parâmetros"
  echo "rede ipt" 
  echo "     >> Executa somente firewall"
  echo "rede dns" 
  echo "     >> Insere registros no DNS e reinicia"
  echo "rede dhcp" 
  echo "     >> Insere registros no DHCP e reinicia"
  echo "rede marcar" 
  echo "     >> Marca pacotes"
  echo "rede help" 
  echo "     >> Exibe esse help"
  echo "rede (Sem parametros)"
  echo "     >> Executa todos"
  exit 1
}

#
# ------------------------------------------------------------------------------------
#                          ..::  M  A  I  N ::..
# ------------------------------------------------------------------------------------


# -----------------------------------------
# SELECIONA PARAMETROS
# -----------------------------------------
case "$1" in
  ipt)
    bipt=true
    ;;
  dns)
    bdns=true
    ;;
  dhcp)
    bdhcp=true
    ;;
  marcar)
    cabecalho_s
    # redirecionar porta 80 pra captive portal
    # recebe MAC=$2, IP=$3 
    # ipt_marcar $mac $ip $nome $desc $status
    ipt_marcar $2 $3 "" "" $STATUS_LOGIN_CP
    exit 0
    ;;
  #liberar)
  #  cabecalho_s
  #  # liberar internet pelo captive portal
  #  # recebe MAC=$2, IP=$3, NOME=$4 e $5=CAPTIVE
  #  # envia ip pra pegar ultimo octeto do IP e mascarar
  #  # ipt_masq $mac $ip $nome
  #  ipt_masq $2 $3 $4
  #  exit 0
  #  ;;
  help)
    uso
    ;;
  *)
    # executa tudo
    bipt=true
    bdns=true
    bdhcp=true
esac

# -----------------------------------------
# COMECA
# -----------------------------------------

# imprime cabecalho com o nome dbIT
cabecalho_s

# muda serial
if [[ $bdns ]]; then
  dns_inc_serial $FZONA1_H 
  dns_inc_serial $FZONA2_H
  dns_cabeca
fi

# cabeca dhcp
if [[ $bdhcp ]]; then
  dhcp_cabeca
fi

# inicializa iptables
if [[ $bipt ]]; then
  ipt_init
fi

# loop do arquivo de rede
loop_s # imprimir texto loop

# -----------------------------------------
# L O O P
IFS="|"
while read mac ip nome desc status
do
  # pula linhas vazias
  [[ $mac = "" ]] && continue
  # pula comentarios
  [[ "$mac" == "#"* ]] && continue
  
  # insere registros dhcp, dns, etc
  reg $mac $ip $nome $desc $status

  # libera ou bloqueia internet de estacao
  if [[ $bipt ]]; then
    ipt_marcar $mac $ip $nome $desc $status
  fi
done < $FREDE
# F I M   L O O P
# -----------------------------------------

if [[ $bipt ]]; then
  # mascara para q estacoes q tiverem com pacotes marcados poderem navegar
  ipt_masq
  # redireciona todo o restante para uaitube.com
  ipt_redir
fi

cabecalho_s # mostra cabelho com o nome dbIT

# -----------------------------------------
# ordem pra reiniciar eh importante, dns tem q ser antes do dhcp server
# pois o ip o dhcp server busca dentro do bind
elinha
echo "REINICIAR SERVICOS"
if [[ $bdns ]]; then
  elinha
  echo -e "$TDNS Reiniciar"
  mv2 $FZONA1 "/etc/bind/zones/db.c.net"
  mv2 $FZONA2 "/etc/bind/zones/db.172.16"
  service bind9 restart
fi
if [[ $bdhcp ]]; then
  elinha
  echo -e "$TDHCP Reiniciar"
  mv2 $FDHCP "/etc/dhcp/dhcpd.conf"
  service isc-dhcp-server restart
fi

# ------------------------------------------------------------------------------------
#                        F I M     M  A  I  N
# ------------------------------------------------------------------------------------

elinha
echo "Pronto."
