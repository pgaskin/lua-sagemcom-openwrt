# lua-sagemcom-openwrt

OpenWRT Lua library for controlling Sagemcom routers.

Tested against the Bell Giga Hub 4000 (F@ST 5689E) firmware 1.19.6 (gui 7.3.28, guiapi 1.106).

Has basic error handling, but expects responses to be well-formed in general.

#### How to automatically disable radios on wan connection

- Copy [`sagemcom.lua`](./sagemcom.lua) and [`sha2.lua`](./sha2.lua) to `/usr/lib/lua`.
- Copy [`set_sagemcom_radios.lua`](./set_sagemcom_radios.lua) to `/usr/bin/set_sagemcom_radios`.
- `opkg update && opkg install luci-lib-base luci-lib-httpclient and luci-lib-json`.
- Create `/etc/hotplug.d/iface/90-sagemcom-radios` (replace wan/admin/password with your values):
  ```shell
  #!/bin/sh
  [ "$ACTION" = "ifup" -a "$INTERFACE" = "wan" ] && {
    { set_sagemcom_radios 192.168.2.1 admin password off 2>&1 || echo exit status $? ; } | while read x
    do
      echo "(set_sagemcom_radios) $x" > /dev/kmsg
      echo "$x" | logger -t set_sagemcom_radios
    done
  }
  exit 0
  ```
- `chmod +x /usr/bin/set_sagemcom_radios /etc/hotplug.d/iface/90-sagemcom-radios`
- `printf '%s\n' '' /usr/lib/lua/sagemcom.lua /usr/lib/lua/sha2.lua /usr/bin/set_sagemcom_radios /etc/hotplug.d/iface/90-sagemcom-radios >> /etc/sysupgrade.conf`
