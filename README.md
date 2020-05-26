# SDR Deployment script

This is a central place for deploying SDR applications (and sul_pub).  This allows all applications
to be deployed at once.

## Usage

Make sure that:
* You are on VPN.
* You have `kinit`-ed.
* You have previously `ssh`-ed into all servers.


```
./deploy.rb stage
```

Note:
* All repos will be cloned to `tmp`. 
* To skip a repo, comment it out in `repos.yml`.
