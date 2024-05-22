from django.urls import path
from .views import home  # Assuming you have a home view in views.py

urlpatterns = [
    path('', home, name='home'),
]