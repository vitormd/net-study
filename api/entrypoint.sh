#!/bin/sh
# A api não termina mais TLS — o gateway (nginx) faz isso. Aqui só sobe Puma.
# Mantém o entrypoint pra ter um lugar simétrico ao do gateway/client.

exec bundle exec puma -C puma.rb config.ru
