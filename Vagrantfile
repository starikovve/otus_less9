# -*- mode: ruby -*-
# vi: set ft=ruby :

Vagrant.configure("2") do |config|
  # Указываем официальный образ Ubuntu 24.04 LTS (Noble Numbat)
  config.vm.box = "ubuntu/jammy64"

  # Конфигурация для VirtualBox
  config.vm.provider "virtualbox" do |vb|
    # Удобное имя для отображения в GUI VirtualBox
    vb.name = "ubuntu-24-homework"
    # Отключаем графический интерфейс (запуск в фоне)
    vb.gui = false
    # Выделяем 2048 МБ оперативной памяти
    vb.memory = "2048"
    # Выделяем 2 ядра процессора
    vb.cpus = 2
  end

  # Запуск скрипта настройки
  # Файл homework.sh должен лежать в той же папке, где и этот Vagrantfile
  config.vm.provision "shell", path: "homework.sh"
end
