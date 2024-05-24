#!/bin/bash
docker build -t yourdockerhubusername/django:${BUILD_NUMBER} .
docker push yourdockerhubusername/django:${BUILD_NUMBER}
