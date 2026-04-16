FROM alpine:3.20

RUN apk add --no-cache \
    postfix \
    dovecot \
    dovecot-lmtpd \
    dovecot-pigeonhole-plugin \
    rspamd \
    redis \
    supervisor \
    bash \
    ca-certificates \
    opendkim \
    opendkim-utils \
    tzdata \
    gettext \
    sed \
    grep

# системные директории
RUN mkdir -p \
    /etc/rspamd \
    /var/lib/rspamd \
    /var/run/rspamd \
    /var/log/rspamd \
    /var/spool/postfix \
    /var/spool/postfix/private \
    /var/mail/vhosts/default.local/user \
    /etc/opendkim/keys/template \
    /etc/dovecot/conf.d \
    /etc/postfix/templates \
    /etc/dovecot.orig

# пользователи
RUN addgroup -S mail && adduser -S mail -G mail || true \
 && addgroup -S postfix && adduser -S postfix -G postfix || true \
 && addgroup -S dovecot && adduser -S dovecot -G dovecot || true

# права на mail storage
RUN chown -R dovecot:mail /var/mail/vhosts

# Postfix → LMTP доставка в Dovecot
RUN postconf -e "mailbox_transport=lmtp:unix:private/lmtp"

# Dovecot конфиг maildir
RUN printf "mail_location = maildir:/var/mail/vhosts/%%d/%%n/Maildir\n" \
"mail_home = /var/mail/vhosts/%%d/%%n\n" \
"mail_uid = dovecot\n" \
"mail_gid = mail\n" \
"mail_privileged_group = mail\n" \
"mail_full_filesystem_access = yes\n" \
"namespace inbox {\n  inbox = yes\n  mailbox Drafts {\n    special_use = \\Drafts\n  }\n  mailbox Junk {\n    special_use = \\Junk\n  }\n  mailbox Sent {\n    special_use = \\Sent\n  }\n  mailbox Trash {\n    special_use = \\Trash\n  }\n}\n" \
> /etc/dovecot/conf.d/10-mail.conf

# Сохраняем оригинальные конфиги Dovecot
RUN mkdir -p /etc/dovecot.orig && cp -r /etc/dovecot/* /etc/dovecot.orig

# bootstrap базовой структуры
RUN mkdir -p \
    /var/mail/vhosts/default.local/user/Maildir/cur \
    /var/mail/vhosts/default.local/user/Maildir/new \
    /var/mail/vhosts/default.local/user/Maildir/tmp \
 && chown -R dovecot:mail /var/mail/vhosts

# Шаблон main.cf с переменными
RUN echo 'myhostname = ${HOSTNAME}' > /etc/postfix/templates/main.cf.tpl && \
    echo 'mydomain = ${DOMAIN}' >> /etc/postfix/templates/main.cf.tpl && \
    echo 'myorigin = ${DOMAIN}' >> /etc/postfix/templates/main.cf.tpl && \
    echo '' >> /etc/postfix/templates/main.cf.tpl && \
    echo 'mydestination = ${HOSTNAME}, localhost.${DOMAIN}, localhost, ${DOMAIN}' >> /etc/postfix/templates/main.cf.tpl && \
    echo '' >> /etc/postfix/templates/main.cf.tpl && \
    echo 'inet_interfaces = all' >> /etc/postfix/templates/main.cf.tpl && \
    echo 'inet_protocols = ipv4' >> /etc/postfix/templates/main.cf.tpl && \
    echo '' >> /etc/postfix/templates/main.cf.tpl && \
    echo 'mynetworks = 127.0.0.0/8, 192.168.254.0/24' >> /etc/postfix/templates/main.cf.tpl && \
    echo '' >> /etc/postfix/templates/main.cf.tpl && \
    echo 'relayhost = ${RELAYHOST}' >> /etc/postfix/templates/main.cf.tpl && \
    echo '' >> /etc/postfix/templates/main.cf.tpl && \
    echo 'smtp_sasl_auth_enable = yes' >> /etc/postfix/templates/main.cf.tpl && \
    echo 'smtp_sasl_mechanism_filter = plain, login' >> /etc/postfix/templates/main.cf.tpl && \
    echo 'smtp_sasl_security_options = noanonymous' >> /etc/postfix/templates/main.cf.tpl && \
    echo '' >> /etc/postfix/templates/main.cf.tpl && \
    echo 'smtp_tls_security_level = encrypt' >> /etc/postfix/templates/main.cf.tpl && \
    echo 'smtp_tls_CAfile = /etc/ssl/certs/ca-certificates.crt' >> /etc/postfix/templates/main.cf.tpl && \
    echo '' >> /etc/postfix/templates/main.cf.tpl && \
    echo 'smtpd_tls_security_level = may' >> /etc/postfix/templates/main.cf.tpl && \
    echo 'smtpd_tls_auth_only = yes' >> /etc/postfix/templates/main.cf.tpl && \
    echo '' >> /etc/postfix/templates/main.cf.tpl && \
    echo 'smtpd_sasl_auth_enable = yes' >> /etc/postfix/templates/main.cf.tpl && \
    echo 'smtpd_sasl_type = dovecot' >> /etc/postfix/templates/main.cf.tpl && \
    echo 'smtpd_sasl_path = private/auth' >> /etc/postfix/templates/main.cf.tpl && \
    echo 'smtpd_sasl_security_options = noanonymous' >> /etc/postfix/templates/main.cf.tpl && \
    echo '' >> /etc/postfix/templates/main.cf.tpl && \
    echo 'smtpd_recipient_restrictions =' >> /etc/postfix/templates/main.cf.tpl && \
    echo '    permit_mynetworks' >> /etc/postfix/templates/main.cf.tpl && \
    echo '    permit_sasl_authenticated' >> /etc/postfix/templates/main.cf.tpl && \
    echo '    reject_unauth_destination' >> /etc/postfix/templates/main.cf.tpl && \
    echo '' >> /etc/postfix/templates/main.cf.tpl && \
    echo 'home_mailbox = Maildir/' >> /etc/postfix/templates/main.cf.tpl && \
    echo 'mailbox_transport = lmtp:unix:private/lmtp' >> /etc/postfix/templates/main.cf.tpl && \
    echo '' >> /etc/postfix/templates/main.cf.tpl && \
    echo 'smtpd_milters = unix:opendkim/opendkim.sock, inet:localhost:11332' >> /etc/postfix/templates/main.cf.tpl && \
    echo 'non_smtpd_milters = unix:opendkim/opendkim.sock' >> /etc/postfix/templates/main.cf.tpl && \
    echo '' >> /etc/postfix/templates/main.cf.tpl && \
    echo 'compatibility_level = 3.9' >> /etc/postfix/templates/main.cf.tpl

# Шаблон opendkim.conf
RUN echo 'Domain                  ${DOMAIN}' > /etc/opendkim.conf.tpl && \
    echo 'KeyFile                 /etc/opendkim/keys/${DOMAIN}/mail.private' >> /etc/opendkim.conf.tpl && \
    echo 'Selector                mail' >> /etc/opendkim.conf.tpl && \
    echo 'Socket                  local:/var/spool/postfix/opendkim/opendkim.sock' >> /etc/opendkim.conf.tpl && \
    echo 'UMask                   002' >> /etc/opendkim.conf.tpl && \
    echo 'UserID                  root' >> /etc/opendkim.conf.tpl

# Скрипт инициализации с export
RUN echo '#!/bin/sh' > /etc/init.sh && \
    echo '' >> /etc/init.sh && \
    echo 'export DOMAIN=${DOMAIN:-cargo-port.eu}' >> /etc/init.sh && \
    echo 'export HOSTNAME=${HOSTNAME:-mail.$DOMAIN}' >> /etc/init.sh && \
    echo 'export RELAYHOST=${RELAYHOST:-[smtp.gmail.com]:587}' >> /etc/init.sh && \
    echo 'export GMAIL_AUTH=${GMAIL_AUTH}' >> /etc/init.sh && \
    echo '' >> /etc/init.sh && \
    echo 'echo "Initializing mail stack for domain: $DOMAIN"' >> /etc/init.sh && \
    echo 'echo "Hostname: $HOSTNAME"' >> /etc/init.sh && \
    echo 'echo "Relayhost: $RELAYHOST"' >> /etc/init.sh && \
    echo '' >> /etc/init.sh && \
    echo '# Восстановление конфигов Dovecot из оригиналов если маунт пустой' >> /etc/init.sh && \
    echo 'if [ ! -f /etc/dovecot/dovecot.conf ]; then' >> /etc/init.sh && \
    echo '    echo "Restoring default dovecot config from /etc/dovecot.orig"' >> /etc/init.sh && \
    echo '    cp -r /etc/dovecot.orig/* /etc/dovecot/' >> /etc/init.sh && \
    echo 'fi' >> /etc/init.sh && \
    echo '' >> /etc/init.sh && \
    echo 'envsubst < /etc/postfix/templates/main.cf.tpl > /etc/postfix/main.cf' >> /etc/init.sh && \
    echo 'envsubst < /etc/opendkim.conf.tpl > /etc/opendkim.conf' >> /etc/init.sh && \
    echo '' >> /etc/init.sh && \
    echo 'if [ ! -f /etc/opendkim/keys/$DOMAIN/mail.private ]; then' >> /etc/init.sh && \
    echo '    echo "Generating DKIM keys for $DOMAIN"' >> /etc/init.sh && \
    echo '    mkdir -p /etc/opendkim/keys/$DOMAIN' >> /etc/init.sh && \
    echo '    cd /etc/opendkim/keys/$DOMAIN' >> /etc/init.sh && \
    echo '    opendkim-genkey -s mail -d $DOMAIN' >> /etc/init.sh && \
    echo '    echo "=== DKIM DNS record for $DOMAIN ==="' >> /etc/init.sh && \
    echo '    cat mail.txt' >> /etc/init.sh && \
    echo '    echo "=================================="' >> /etc/init.sh && \
    echo 'fi' >> /etc/init.sh && \
    echo '' >> /etc/init.sh && \
    echo '# Создание сокета для OpenDKIM' >> /etc/init.sh && \
    echo 'mkdir -p /var/spool/postfix/opendkim' >> /etc/init.sh && \
    echo 'chown opendkim:opendkim /var/spool/postfix/opendkim' >> /etc/init.sh && \
    echo 'chmod 750 /var/spool/postfix/opendkim' >> /etc/init.sh && \
    echo 'usermod -aG opendkim postfix' >> /etc/init.sh && \
    echo '' >> /etc/init.sh && \
    echo 'chmod 755 /etc /etc/opendkim /etc/opendkim/keys' >> /etc/init.sh && \
    echo 'chmod 755 /etc/opendkim/keys/$DOMAIN' >> /etc/init.sh && \
    echo 'chmod 600 /etc/opendkim/keys/$DOMAIN/mail.private' >> /etc/init.sh && \
    echo '' >> /etc/init.sh && \
    echo '/usr/sbin/opendkim -f -x /etc/opendkim.conf &' >> /etc/init.sh && \
    echo '' >> /etc/init.sh && \
    echo 'if [ ! -z "$GMAIL_AUTH" ]; then' >> /etc/init.sh && \
    echo '    echo "$RELAYHOST    $GMAIL_AUTH" > /etc/postfix/sasl_passwd' >> /etc/init.sh && \
    echo '    chmod 600 /etc/postfix/sasl_passwd' >> /etc/init.sh && \
    echo '    postmap lmdb:/etc/postfix/sasl_passwd' >> /etc/init.sh && \
    echo '    postconf -e smtp_sasl_password_maps=lmdb:/etc/postfix/sasl_passwd' >> /etc/init.sh && \
    echo '    echo "Gmail SASL auth configured"' >> /etc/init.sh && \
    echo 'fi' >> /etc/init.sh && \
    echo '' >> /etc/init.sh && \
    echo 'postfix reload' >> /etc/init.sh && \
    echo '' >> /etc/init.sh && \
    echo 'echo "Mail stack initialized"' >> /etc/init.sh

RUN chmod +x /etc/init.sh

COPY supervisord.conf /etc/supervisord.conf

EXPOSE 25 587 143 993

CMD ["/usr/bin/supervisord", "-c", "/etc/supervisord.conf"]
