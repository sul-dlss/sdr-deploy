# SDR Deployment script

This is a central place for deploying SDR applications (and sul_pub).  This allows all applications
to be deployed at once.

## Setup

Install required gems:

```shell
$ gem install bundler
$ bundle install
```

## Usage

Make sure that:
* You are on VPN.
* You have `kinit`-ed.
* You have added the public SSH key, often `~/.ssh/id_rsa.pub`, from your machine to [GitHub](https://github.com/settings/keys)
* You have previously `ssh`-ed into all servers.
  * NOTE: If you are unsure about this, run `./deploy.rb stage --checkssh` and watch the output for any errors!

```
./deploy.rb stage
```

Note:
* All repos will be cloned to `tmp`.
* To skip a repo, comment it out in `repos.yml`.
