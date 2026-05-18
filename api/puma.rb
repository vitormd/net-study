# A api agora fala HTTP puro — quem termina mTLS é o gateway (nginx) na frente.
# Esse é o padrão de produção: app não toca em TLS, sidecar/ingress cuida.
#
# Porta 8000: tráfego "pós-mTLS" vindo do gateway, com headers XFCC.
# Porta 4000: plano de controle (probe, allowlist, interfaces).

bind 'tcp://[::]:8000'
bind 'tcp://[::]:4000'

threads 2, 8
workers 0
log_requests false
