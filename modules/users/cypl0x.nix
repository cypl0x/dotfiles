{ pkgs, ... }: {
  users.users.cypl0x = {
    isNormalUser = true;
    description = "Wolfhard Prell";
    extraGroups = [ "networkmanager" "wheel" "docker" ];
    shell = pkgs.zsh;
    openssh.authorizedKeys.keys = [
      "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDHOc2Af91XVXmUxuCiKeELkM6b+zVK1ob9ciicNcyIdew4MdSkA1M4GkZQ5TRigqCV8245DHTzgQcHD5/+WCv4X6NC7nihxFDpGXt1ywnjtwoZH8U0c2BdhU7pAmHMJCeiZaBkuaEVdTtR/7NBLtFHeDx+rnGB9Ghp4As2tJi+Ds1GBqHBww7kCmGxxku5uqLal6QIGb8M9TfcXzWObOj6sZQPpOsUHwuDVB7TGFNItworFLO0QgRzndGhjMF/cDxktbDPfq4Bsf3fk8G/r/t920syGswToZwNTIeTgw4qOQTpwu6g0NgnqRFtSLU2xmFSRvtKaR1pf7lbQu79wNNqEs/Fu03QwmVfuhWfK+R+DQw4e3m3K6hwv4EfVspe72jAoQPSWU+d++CEutVeLb3CLNPCEWID34YcDyQxSH5dr0++XE1qRz05WMyzt9PkDV4RU8Wf4awIJA7lEnvF/2tZU1AIOqo8JKWja6JawN0OkWohTlDfiHs2pz9pFQgy4VXxI543SeehVB0tPNFTb5Si4jX8n4X9+834wqlVFwFqFZL+3ZGmxpXvMVwMFr28unzq7/bS+p2Cj5dwNUtmt9Ac+7D38db0/yCj1rBOfmMOfOhuYw4HYcBp65z2c6ZHMI4FeWp9ApHl3Fn519pixhnZNw2igFitnHoBnomUNmbeNQ== homelab"
    ];
  };
}
