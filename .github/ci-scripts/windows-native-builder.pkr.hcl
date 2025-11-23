
variable "tessell_mysql_db_username" {
  description = "Username for Tessell MySQL database"
  default     = env("TESSELL_MYSQL_DB_USERNAME")
}

variable "tessell_mysql_db_password" {
  description = "Password for Tessell MySQL database"
  default     = env("TESSELL_MYSQL_DB_PASSWORD")
  sensitive   = true
}

source "amazon-ebs" "windows-builder" {
  region         = "ap-south-1"
  source_ami     = "ami-03d3615b6028a7af3"
  instance_type  = "c5.4xlarge"
  communicator   = "winrm"
  winrm_username = "TessellMssql"
  winrm_password = "AWSMSSQL82wnellxrVaRMZpQ"
  # profile        = 402291221517
  ami_name       = "native-build-{{timestamp}}"
  winrm_insecure = true
  skip_create_ami = true
  run_tags = {
    Name = "windows-native-builder-2"
  }
}

build {
  name    = "windows-native-builder-2"
  sources = ["source.amazon-ebs.windows-builder"]
  #####################################
  # Upload repo ZIP
  #####################################
  provisioner "file" {
    source      = "repo.zip"
    destination = "C:\\Users\\Administrator\\repo.zip"
  }

  # #####################################
  # # Upload environment variables file
  # #####################################
  # provisioner "file" {
  #   source      = "envvars.ps1"
  #   destination = "C:\\Users\\Administrator\\envvars.ps1"
  # }

  # #####################################
  # # Upload build script
  # #####################################
  # provisioner "file" {
  #   source      = "build.ps1"
  #   destination = "C:\\Users\\Administrator\\build.ps1"
  # }

  #####################################
  # Main execution
  #####################################
  provisioner "powershell" {
    inline = [
      "$ErrorActionPreference = 'Stop'",

      "Write-Host '📦 Extracting repo.zip using 7-Zip...'",
      "& 'C:\\Program Files\\7-Zip\\7z.exe' x 'C:\\Users\\Administrator\\repo.zip' -oC:\\Users\\Administrator\\repo -y",

      "Write-Host '🚀 Running build script...'",
      ". C:\\Users\\Administrator\\repo\\convoy-scripts\\build.ps1",

      "Write-Host '🪣 Zipping output folder with 7-Zip...'",
      "& 'C:\\Program Files\\7-Zip\\7z.exe' a -tzip 'C:\\Users\\Administrator\\output.zip' 'C:\\Users\\Administrator\\output\\*' -mx=9",

      "Write-Host '🎉 Zipped output ready at C:\\Users\\Administrator\\output.zip'"
    ]
  }

  provisioner "file" {
    source      = "C:\\Users\\Administrator\\output.zip"
    destination = "./output.zip"
    direction   = "download"
  }
}
