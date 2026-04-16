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
    tzdata \
    gettext \
    sed \
    grep \
    curl \
    fail2ban \
    opendkim \
    opendkim-utils

# Настройка часового пояса
ENV TZ=Europe/Moscow
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

# системные директории
RUN mkdir -p \
    /etc/rspamd \
    /var/lib/rspamd \
    /var/run/rspamd \
    /var/log/rspamd \
    /var/spool/postfix \
    /var/spool/postfix/private \
    /var/mail/vhosts/default.local/user \
    /etc/dovecot/conf.d \
    /etc/postfix/templates \
    /etc/dovecot.orig \
    /etc/opendkim/keys/cargo-port.eu

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

# Настройка квот и автоочистки Trash
RUN echo 'mail_plugins = $mail_plugins quota' > /etc/dovecot/conf.d/90-quota.conf && \
    echo '' >> /etc/dovecot/conf.d/90-quota.conf && \
    echo 'protocol imap {' >> /etc/dovecot/conf.d/90-quota.conf && \
    echo '  mail_plugins = $mail_plugins imap_quota' >> /etc/dovecot/conf.d/90-quota.conf && \
    echo '}' >> /etc/dovecot/conf.d/90-quota.conf && \
    echo '' >> /etc/dovecot/conf.d/90-quota.conf && \
    echo 'plugin {' >> /etc/dovecot/conf.d/90-quota.conf && \
    echo '  quota_rule = *:storage=3G' >> /etc/dovecot/conf.d/90-quota.conf && \
    echo '  quota_rule2 = Trash:storage=+300M' >> /etc/dovecot/conf.d/90-quota.conf && \
    echo '}' >> /etc/dovecot/conf.d/90-quota.conf

# Настройка Rspamd (спам-фильтр и DKIM)
RUN echo 'reject = 15;' > /etc/rspamd/local.d/actions.conf && \
    echo 'add_header = 6;' >> /etc/rspamd/local.d/actions.conf && \
    echo 'spam = 6;' >> /etc/rspamd/local.d/actions.conf

# Настройка DKIM в Rspamd
RUN mkdir -p /etc/rspamd/local.d && \
    echo 'enabled = true;' > /etc/rspamd/local.d/dkim_signing.conf && \
    echo 'sign_authenticated = true;' >> /etc/rspamd/local.d/dkim_signing.conf && \
    echo 'sign_local = true;' >> /etc/rspamd/local.d/dkim_signing.conf && \
    echo '' >> /etc/rspamd/local.d/dkim_signing.conf && \
    echo 'domain {' >> /etc/rspamd/local.d/dkim_signing.conf && \
    echo '  cargo-port.eu {' >> /etc/rspamd/local.d/dkim_signing.conf && \
    echo '    path = "/etc/opendkim/keys/cargo-port.eu/mail.private";' >> /etc/rspamd/local.d/dkim_signing.conf && \
    echo '    selector = "mail";' >> /etc/rspamd/local.d/dkim_signing.conf && \
    echo '  }' >> /etc/rspamd/local.d/dkim_signing.conf && \
    echo '}' >> /etc/rspamd/local.d/dkim_signing.conf

# Настройка Sieve для перемещения спама в Junk
RUN mkdir -p /etc/dovecot/sieve && \
    echo 'require ["fileinto"];' > /etc/dovecot/sieve/default.sieve && \
    echo 'if header :contains "X-Spam" "Yes" {' >> /etc/dovecot/sieve/default.sieve && \
    echo '    fileinto "Junk";' >> /etc/dovecot/sieve/default.sieve && \
    echo '    stop;' >> /etc/dovecot/sieve/default.sieve && \
    echo '}' >> /etc/dovecot/sieve/default.sieve
RUN sievec /etc/dovecot/sieve/default.sieve

# Настройка автоочистки Trash и Junk
RUN echo 'namespace inbox {' > /etc/dovecot/conf.d/15-mailboxes.conf && \
    echo '  mailbox Trash {' >> /etc/dovecot/conf.d/15-mailboxes.conf && \
    echo '    autoexpunge = 30d' >> /etc/dovecot/conf.d/15-mailboxes.conf && \
    echo '  }' >> /etc/dovecot/conf.d/15-mailboxes.conf && \
    echo '  mailbox Junk {' >> /etc/dovecot/conf.d/15-mailboxes.conf && \
    echo '    autoexpunge = 30d' >> /etc/dovecot/conf.d/15-mailboxes.conf && \
    echo '  }' >> /etc/dovecot/conf.d/15-mailboxes.conf && \
    echo '}' >> /etc/dovecot/conf.d/15-mailboxes.conf

# Настройка fail2ban для почты
RUN mkdir -p /etc/fail2ban/jail.d && \
    echo '[DEFAULT]' > /etc/fail2ban/jail.d/local.conf && \
    echo 'bantime = 3600' >> /etc/fail2ban/jail.d/local.conf && \
    echo 'findtime = 600' >> /etc/fail2ban/jail.d/local.conf && \
    echo 'maxretry = 5' >> /etc/fail2ban/jail.d/local.conf && \
    echo '' >> /etc/fail2ban/jail.d/local.conf && \
    echo '[dovecot]' >> /etc/fail2ban/jail.d/local.conf && \
    echo 'enabled = true' >> /etc/fail2ban/jail.d/local.conf && \
    echo 'logpath = /var/log/dovecot/*.log' >> /etc/fail2ban/jail.d/local.conf && \
    echo '' >> /etc/fail2ban/jail.d/local.conf && \
    echo '[postfix-sasl]' >> /etc/fail2ban/jail.d/local.conf && \
    echo 'enabled = true' >> /etc/fail2ban/jail.d/local.conf && \
    echo 'logpath = /var/log/mail.log' >> /etc/fail2ban/jail.d/local.conf

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
    echo 'smtpd_tls_auth_only = no' >> /etc/postfix/templates/main.cf.tpl && \
    echo 'smtpd_tls_cert_file = /etc/postfix/certs/${DOMAIN}.crt' >> /etc/postfix/templates/main.cf.tpl && \
    echo 'smtpd_tls_key_file = /etc/postfix/certs/${DOMAIN}.key' >> /etc/postfix/templates/main.cf.tpl && \
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
    echo 'smtpd_milters = inet:localhost:11332' >> /etc/postfix/templates/main.cf.tpl && \
    echo 'non_smtpd_milters = ' >> /etc/postfix/templates/main.cf.tpl && \
    echo '' >> /etc/postfix/templates/main.cf.tpl && \
    echo 'compatibility_level = 3.9' >> /etc/postfix/templates/main.cf.tpl

# Скрипт инициализации
RUN echo '#!/bin/sh' > /etc/init.sh && \
    echo '' >> /etc/init.sh && \
    echo 'export DOMAIN=${DOMAIN:-cargo-port.eu}' >> /etc/init.sh && \
    echo 'export HOSTNAME=${HOSTNAME:-mail.$DOMAIN}' >> /etc/init.sh && \
    echo 'export RELAYHOST=${RELAYHOST:-[smtp.gmail.com]:587}' >> /etc/init.sh && \
    echo 'export GMAIL_AUTH=${GMAIL_AUTH}' >> /etc/init.sh && \
    echo 'export CF_TOKEN=${CF_TOKEN}' >> /etc/init.sh && \
    echo 'export CF_ZONE_ID=${CF_ZONE_ID}' >> /etc/init.sh && \
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
    echo '' >> /etc/init.sh && \
    echo '# Генерация DKIM ключей если нет' >> /etc/init.sh && \
    echo 'if [ ! -f /etc/opendkim/keys/$DOMAIN/mail.private ]; then' >> /etc/init.sh && \
    echo '    echo "Generating DKIM keys for $DOMAIN"' >> /etc/init.sh && \
    echo '    mkdir -p /etc/opendkim/keys/$DOMAIN' >> /etc/init.sh && \
    echo '    cd /etc/opendkim/keys/$DOMAIN' >> /etc/init.sh && \
    echo '    opendkim-genkey -s mail -d $DOMAIN' >> /etc/init.sh && \
    echo '    chmod 600 mail.private' >> /etc/init.sh && \
    echo '    echo "=== DKIM DNS record for $DOMAIN ==="' >> /etc/init.sh && \
    echo '    cat mail.txt' >> /etc/init.sh && \
    echo '    echo "=================================="' >> /etc/init.sh && \
    echo 'fi' >> /etc/init.sh && \
    echo '' >> /etc/init.sh && \
    echo '# Обновление DKIM в Cloudflare (опционально)' >> /etc/init.sh && \
    echo 'if [ ! -z "$CF_TOKEN" ] && [ ! -z "$CF_ZONE_ID" ]; then' >> /etc/init.sh && \
    echo '    DKIM_VALUE=$(grep -o "p=[^\"]*" /etc/opendkim/keys/$DOMAIN/mail.txt | head -1)' >> /etc/init.sh && \
    echo '    DKIM_CONTENT="v=DKIM1; k=rsa; $DKIM_VALUE"' >> /etc/init.sh && \
    echo '    echo "Updating Cloudflare DNS for $DOMAIN"' >> /etc/init.sh && \
    echo '    RECORD_ID=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID/dns_records?name=mail._domainkey.$DOMAIN&type=TXT" \' >> /etc/init.sh && \
    echo '        -H "Authorization: Bearer $CF_TOKEN" \' >> /etc/init.sh && \
    echo '        -H "Content-Type: application/json" | grep -o "\"id\":\"[^\"]*\"" | head -1 | cut -d"\"" -f4)' >> /etc/init.sh && \
    echo '    if [ -n "$RECORD_ID" ]; then' >> /etc/init.sh && \
    echo '        curl -s -X PUT "https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID/dns_records/$RECORD_ID" \' >> /etc/init.sh && \
    echo '            -H "Authorization: Bearer $CF_TOKEN" \' >> /etc/init.sh && \
    echo '            -H "Content-Type: application/json" \' >> /etc/init.sh && \
    echo '            --data "{\"type\":\"TXT\",\"name\":\"mail._domainkey.$DOMAIN\",\"content\":\"$DKIM_CONTENT\"}" > /dev/null' >> /etc/init.sh && \
    echo '        echo "DKIM record updated in Cloudflare"' >> /etc/init.sh && \
    echo '    else' >> /etc/init.sh && \
    echo '        curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID/dns_records" \' >> /etc/init.sh && \
    echo '            -H "Authorization: Bearer $CF_TOKEN" \' >> /etc/init.sh && \
    echo '            -H "Content-Type: application/json" \' >> /etc/init.sh && \
    echo '            --data "{\"type\":\"TXT\",\"name\":\"mail._domainkey.$DOMAIN\",\"content\":\"$DKIM_CONTENT\"}" > /dev/null' >> /etc/init.sh && \
    echo '        echo "DKIM record created in Cloudflare"' >> /etc/init.sh && \
    echo '    fi' >> /etc/init.sh && \
    echo 'fi' >> /etc/init.sh && \
    echo '' >> /etc/init.sh && \
    echo '# Создание конфига Dovecot для аутентификации' >> /etc/init.sh && \
    echo 'cat > /etc/dovecot/conf.d/10-master.conf << "EOF"' >> /etc/init.sh && \
    echo 'service auth {' >> /etc/init.sh && \
    echo '  unix_listener /var/spool/postfix/private/auth {' >> /etc/init.sh && \
    echo '    mode = 0660' >> /etc/init.sh && \
    echo '    user = postfix' >> /etc/init.sh && \
    echo '    group = postfix' >> /etc/init.sh && \
    echo '  }' >> /etc/init.sh && \
    echo '}' >> /etc/init.sh && \
    echo 'EOF' >> /etc/init.sh && \
    echo '' >> /etc/init.sh && \
    echo '# Добавление порта 587 в master.cf' >> /etc/init.sh && \
    echo 'cat >> /etc/postfix/master.cf << "EOF"' >> /etc/init.sh && \
    echo '587      inet  n       -       n       -       -       smtpd' >> /etc/init.sh && \
    echo '  -o smtpd_tls_wrappermode=no' >> /etc/init.sh && \
    echo '  -o smtpd_sasl_auth_enable=yes' >> /etc/init.sh && \
    echo '  -o smtpd_sasl_type=dovecot' >> /etc/init.sh && \
    echo '  -o smtpd_sasl_path=private/auth' >> /etc/init.sh && \
    echo '  -o smtpd_tls_security_level=may' >> /etc/init.sh && \
    echo 'EOF' >> /etc/init.sh && \
    echo '' >> /etc/init.sh && \
    echo 'chmod 755 /etc /etc/opendkim /etc/opendkim/keys' >> /etc/init.sh && \
    echo 'chmod 755 /etc/opendkim/keys/$DOMAIN' >> /etc/init.sh && \
    echo 'chmod 600 /etc/opendkim/keys/$DOMAIN/mail.private' >> /etc/init.sh && \
    echo '' >> /etc/init.sh && \
    echo 'if [ ! -z "$GMAIL_AUTH" ]; then' >> /etc/init.sh && \
    echo '    echo "$RELAYHOST    $GMAIL_AUTH" > /tmp/sasl_passwd' >> /etc/init.sh && \
    echo '    chmod 600 /tmp/sasl_passwd' >> /etc/init.sh && \
    echo '    postmap lmdb:/tmp/sasl_passwd' >> /etc/init.sh && \
    echo '    cp /tmp/sasl_passwd.lmdb /etc/postfix/sasl_passwd.lmdb' >> /etc/init.sh && \
    echo '    rm -f /tmp/sasl_passwd /tmp/sasl_passwd.lmdb' >> /etc/init.sh && \
    echo '    postconf -e smtp_sasl_password_maps=lmdb:/etc/postfix/sasl_passwd' >> /etc/init.sh && \
    echo '    echo "Gmail SASL auth configured"' >> /etc/init.sh && \
    echo 'fi' >> /etc/init.sh && \
    echo '' >> /etc/init.sh && \
    echo '# Запуск fail2ban' >> /etc/init.sh && \
    echo 'if [ ! -f /var/run/fail2ban/fail2ban.sock ]; then' >> /etc/init.sh && \
    echo '    fail2ban-client -x start' >> /etc/init.sh && \
    echo '    echo "fail2ban started"' >> /etc/init.sh && \
    echo 'fi' >> /etc/init.sh && \
    echo '' >> /etc/init.sh && \
    echo 'postfix reload' >> /etc/init.sh && \
    echo '' >> /etc/init.sh && \
    echo 'echo "Mail stack initialized"' >> /etc/init.sh

RUN chmod +x /etc/init.sh

COPY supervisord.conf /etc/supervisord.conf

EXPOSE 25 587 143 993

CMD ["/usr/bin/supervisord", "-c", "/etc/supervisord.conf"]
