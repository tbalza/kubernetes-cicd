#!/bin/bash

# Run Django collectstatic
echo "Collecting static files..."
python manage.py collectstatic --noinput --clear

# Start Gunicorn server
echo "Starting Gunicorn server..."
exec gunicorn myproject.wsgi:application --bind 0.0.0.0:8000