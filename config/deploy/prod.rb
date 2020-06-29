server 'sdr-deploy.stanford.edu', user: 'deploy', roles: %w[app]

Capistrano::OneTimeKey.generate_one_time_key!
