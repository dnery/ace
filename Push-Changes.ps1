$user = 'danilo'
$remote = 'ace'
$projects = 'danilo-portfolio-2025-session-arena'
$compose_up_cmd = 'docker compose up -d --build'


# update caddy
scp -p Caddyfile ${user}@${remote}:`~/Caddyfile
ssh ${user}@$remote "sudo cp /etc/caddy/Caddyfile /etc/caddy/Caddyfile.bak"
ssh ${user}@$remote "sudo mv `~/Caddyfile /etc/caddy/Caddyfile; and sudo systemctl reload caddy"


# update submodules
foreach ($project in $projects) {
	ssh ${user}@$remote "mkdir -p `~/$project"
	scp -p ../${project}/.env ${user}@${remote}:`~/${project}/.env
	scp -p ../${project}/compose.yaml ${user}@${remote}:`~/${project}/compose.yaml
	ssh ${user}@$remote "cd `~/${project}; and $compose_up_cmd"
}


# update compose & restart
scp -p compose.yaml ${user}@${remote}:`~/compose.yaml
ssh ${user}@$remote "cd `~/; and $compose_up_cmd"
