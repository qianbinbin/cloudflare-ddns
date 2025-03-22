# cloudflare-ddns

Dynamically update your DNS records in Cloudflare.

## Usage

[Create a Cloudflare API token](https://developers.cloudflare.com/fundamentals/api/get-started/create-token/)

### Manually

Download the script:

```sh
curl https://raw.githubusercontent.com/qianbinbin/cloudflare-ddns/refs/heads/master/cloudflare-ddns.sh \
  -o ~/.local/bin/cloudflare-ddns
chmod +x ~/.local/bin/cloudflare-ddns
```

Run:

```sh
export CLOUDFLARE_API_TOKEN=YOUR_TOKEN # you can add this as an environment variable
cloudflare-ddns --zone-name example.com --record-name ddns.example.com
```

### Manage with systemd

Supposing you want to update the record `ddns.example.com`, run as root to install:

```sh
mkdir -p /usr/local/bin /usr/local/lib/systemd/system /usr/local/etc/cloudflare-ddns
chmod 700 /usr/local/etc/cloudflare-ddns
curl https://raw.githubusercontent.com/qianbinbin/cloudflare-ddns/refs/heads/master/cloudflare-ddns.sh \
  -o /usr/local/bin/cloudflare-ddns \
  https://raw.githubusercontent.com/qianbinbin/cloudflare-ddns/refs/heads/master/cloudflare-ddns@.service \
  -o /usr/local/lib/systemd/system/cloudflare-ddns@.service \
  https://raw.githubusercontent.com/qianbinbin/cloudflare-ddns/refs/heads/master/cloudflare-ddns.conf \
  -o /usr/local/etc/cloudflare-ddns/ddns.example.com # save with the same name as your record
chmod +x /usr/local/bin/cloudflare-ddns
systemctl daemon-reload
```

Set your CLOUDFLARE\_API\_TOKEN environment variable and options in `/usr/local/etc/cloudflare-ddns/ddns.example.com`:

```
CLOUDFLARE_API_TOKEN=YOUR_TOKEN
CFDDNS_OPTS=--zone-name example.com --record-name ddns.example.com
```

Then:

```sh
systemctl enable cloudflare-ddns@ddns.example.com.service # start up on boot
systemctl start cloudflare-ddns@ddns.example.com.service
systemctl status cloudflare-ddns@ddns.example.com.service
```

To update more records, place the configuration files under `/usr/local/etc/cloudflare-ddns/` and manage the instances with systemd.

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

  # update AAAA record for 'ddns.example.com' and notify admin
  cloudflare-ddns -z example.com -r ddns.example.com -6 -m admin

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
  -m, --mail-to <addr>      send an email to <addr> when a record is created or
                            renewed; <addr> can be a user or an email address
                            (MTA configuration required for email); can be used
                            several times
  -h, --help                display this help and exit

Home page: <https://github.com/qianbinbin/cloudflare-ddns>
```
