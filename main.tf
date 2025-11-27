terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

provider "google" {
  credentials = file("key.json")
  project = "terraform-479314" 
  region  = "europe-north1"
  zone    = "europe-north1-a"
}

resource "google_compute_network" "vpc_network" {
  name                    = "instance-vpc-network" 
  auto_create_subnetworks = true
}

resource "google_compute_instance" "app_servers" {
  count         = 2 
  
  name          = "app-server-${count.index}"
  machine_type  = "e2-micro"
  zone          = "europe-north1-a"

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-11"
    }
  }

  network_interface {
    network = google_compute_network.vpc_network.id
    access_config {}
  }

  // Установка Nginx
  metadata = {
    startup-script = <<-EOF
        #!/bin/bash
        sudo apt update
        sudo apt install -y nginx
        echo "<h1>Hello TO Olexandra_Devops_guru ${count.index} (Serving via Load Balancer)</h1>" | sudo tee /var/www/html/index.html
    EOF
  }
}

resource "google_compute_firewall" "allow_ssh" {
  name    = "allow-ssh-ingress-app"
  network = google_compute_network.vpc_network.name
  allow {
    protocol = "tcp"
    ports    = ["22"] 
  }
  source_ranges = ["0.0.0.0/0"]
}

resource "google_compute_firewall" "allow_http" {
  name    = "allow-http-ingress-app"
  network = google_compute_network.vpc_network.name
  allow {
    protocol = "tcp"
    ports    = ["80"]
  }
  source_ranges = ["0.0.0.0/0"] 
}

resource "google_compute_instance_group" "instance_group" {
  name    = "web-instance-group"
  zone    = "europe-north1-a"

  instances = [
    google_compute_instance.app_servers[0].self_link,
    google_compute_instance.app_servers[1].self_link,
  ]
}

// 2.2. Health Check (Проверка состояния)
resource "google_compute_region_health_check" "http_health_check_modern" {
  name   = "http-basic-check-modern"
  region = "europe-north1" 

  http_health_check {
    port = 80
  }
}

resource "google_compute_region_backend_service" "web_backend" {
  name        = "web-backend-service"
  protocol    = "HTTP"
  region      = "europe-north1"
  health_checks = [google_compute_region_health_check.http_health_check_modern.self_link]

  backend {
    group = google_compute_instance_group.instance_group.self_link
  }
}

resource "google_compute_region_url_map" "url_map" {
  name            = "web-url-map"
  region          = "europe-north1"
  default_service = google_compute_region_backend_service.web_backend.self_link
}

resource "google_compute_region_target_http_proxy" "http_proxy" {
  name    = "http-target-proxy"
  region  = "europe-north1"
  url_map = google_compute_region_url_map.url_map.self_link
}

resource "google_compute_forwarding_rule" "forwarding_rule_modern" {
  name        = "http-forwarding-rule-modern"
  region      = "europe-north1"
  port_range  = "80"
  target      = google_compute_region_target_http_proxy.http_proxy.self_link
}

output "load_balancer_ip" {
  description = "The external IP address of the Regional Load Balancer"
  value       = google_compute_forwarding_rule.forwarding_rule_modern.ip_address
}

output "instance_ips" {
  description = "External IP addresses of the created instances (for debugging)"
  value = google_compute_instance.app_servers[*].network_interface.0.access_config.0.nat_ip
}
