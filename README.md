# cloudflare-ddns

Dynamically update your DNS records in Cloudflare.

## Usage

Run as root to install:

```sh
mkdir -p /usr/local/lib/systemd/system
curl https://raw.githubusercontent.com/qianbinbin/cloudflare-ddns/refs/heads/master/cloudflare-ddns.sh \
-o /usr/local/bin/cloudflare-ddns \
https://raw.githubusercontent.com/qianbinbin/cloudflare-ddns/refs/heads/master/cloudflare-ddns.service \
-o /usr/local/lib/systemd/system/cloudflare-ddns.service \
https://raw.githubusercontent.com/qianbinbin/cloudflare-ddns/refs/heads/master/cloudflare-ddns.env \
-o /etc/defaults/cloudflare-ddns
chmod +x /usr/local/bin/cloudflare-ddns
chmod 600 /etc/defaults/cloudflare-ddns
systemctl daemon-reload
```

[Create an API token](https://developers.cloudflare.com/fundamentals/api/get-started/create-token/),
then set your CLOUDFLARE\_API\_TOKEN environment variable and options in `/etc/defaults/cloudflare-ddns`.

Manage with systemd:

```sh
systemctl enable cloudflare-ddns.service # start up on boot
systemctl start cloudflare-ddns.service
systemctl status cloudflare-ddns.service
```

Or run manually:

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
  cloudflare-ddns --zone-name example.com --record-name ddns.example.com

Options:
      --zone-name <name>    zone name
      --zone-id <id>        zone ID; if not set, the ID will be retrieved with
                            --zone-name; this option takes higher precedence
                            than --zone-name
      --record-name <name>  record name
      --record-id <id>      record ID; if not set, the ID will be the first A
                            record retrieved with --record-name, or create a new
                            one if no records found; this option takes higher
                            precedence than --record-name
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
