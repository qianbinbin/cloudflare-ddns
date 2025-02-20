# cloudflare-ddns

Dynamically update your DNS records in Cloudflare.

## Usage

Take a Debian-based Linux as an example, run as root to install:

```sh
mkdir -p /usr/local/bin /usr/local/lib/systemd/system
curl https://raw.githubusercontent.com/qianbinbin/cloudflare-ddns/refs/heads/master/cloudflare-ddns.sh \
-o /usr/local/bin/cloudflare-ddns \
https://raw.githubusercontent.com/qianbinbin/cloudflare-ddns/refs/heads/master/cloudflare-ddns.service \
-o /usr/local/lib/systemd/system/cloudflare-ddns.service \
https://raw.githubusercontent.com/qianbinbin/cloudflare-ddns/refs/heads/master/cloudflare-ddns.conf \
-o /etc/defaults/cloudflare-ddns # configuration file on Debian-based Linux
chmod +x /usr/local/bin/cloudflare-ddns
chmod 600 /etc/defaults/cloudflare-ddns
systemctl daemon-reload
```

If you want to place the configuration file in a different location,
don't forget to modify the `cloudflare-ddns.service`:

```
EnvironmentFile=/etc/default/cloudflare-ddns
```

[Create an API token](https://developers.cloudflare.com/fundamentals/api/get-started/create-token/),
then set your CLOUDFLARE\_API\_TOKEN environment variable and options in the configuration file:

```
CLOUDFLARE_API_TOKEN=YOUR_TOKEN
CFDDNS_OPTS=--zone-name example.com --record-name ddns.example.com
```

Manage with systemd:

```sh
systemctl enable cloudflare-ddns.service # start up on boot
systemctl start cloudflare-ddns.service
systemctl status cloudflare-ddns.service
```

You can also run it manually:

```sh
export CLOUDFLARE_API_TOKEN=YOUR_TOKEN
cloudflare-ddns --zone-name example.com --record-name ddns.example.com
```

## Options

```
Usage: cloudflare-ddns [OPTION]...

Dynamically update your DNS records in Cloudflare.

Create an API token and set your CLOUDFLARE_API_TOKEN environment variable
before running this script. For more details, refer to
<https://developers.cloudflare.com/fundamentals/api/get-started/create-token/>

Examples:
  # update A record for 'ddns.example.com'
  cloudflare-ddns --zone-name example.com --record-name ddns.example.com

  # update AAAA record for 'ddns.example.com'
  cloudflare-ddns -z example.com -r ddns.example.com -6

  # update both A and AAAA records for 'ddns.example.com'
  cloudflare-ddns -z example.com -r ddns.example.com -4 -6

Options:
  -z, --zone-name <name>    zone name
  -r, --record-name <name>  record name; if A/AAAA records already exist in
                            Cloudflare, update the first one; see also --ipv4
                            and --ipv6
  -4, --ipv4                update A record (default)
  -6, --ipv6                update AAAA record only when used without --ipv4, or
                            update both A and AAAA records when used with --ipv4
  -p, --proxy               enable Cloudflare proxy for the record
  -t, --ttl <num>           Time To Live (TTL) of the DNS record in seconds;
                            setting to 1 means 'automatic'; value must be
                            between 60 and 86400, with the minimum reduced to 30
                            for Enterprise zones (default: 1)
  -i, --renew-interval <num>
                            renew interval in seconds (default: 300)
  -h, --help                display this help and exit

Home page: <https://github.com/qianbinbin/cloudflare-ddns>
```
