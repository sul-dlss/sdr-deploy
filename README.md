# SDR Deployment script

This is a central place for deploying SDR applications (and sul_pub).  This allows all applications
to be deployed together in a single script.

## Usage

Make sure that:
* You are on VPN.
* You have `kinit`-ed.
* You have added the public SSH key, often `~/.ssh/id_rsa.pub`, from your machine to [GitHub](https://github.com/settings/keys)
* You have previously `ssh`-ed into all servers.
  * NOTE: If you are unsure about this, run `./deploy.rb [qa|stage|prod] --checkssh` and watch the output for any errors!

### Check your ssh connection to all servers

```
./deploy.rb [qa|stage|prod] --checkssh
```

NOTE: Watch the output for any errors

### Check versions of cocina

```
./deploy.rb [qa|stage|prod] --check-cocina
```

This will let you know which versions of cocina each project is locked to.


### Run the deploys

```
./deploy.rb qa   # or stage or prod
```

Note:
* All repos will be cloned to `tmp`.
* To skip a repo, comment it out in `repos.yml`.
* if you prefer your output in color, this will work:
```
export SSHKIT_COLOR='TRUE'
```
