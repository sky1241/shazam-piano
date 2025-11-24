"""
Tests for FastAPI endpoints
"""
import pytest
from fastapi.testclient import TestClient
from pathlib import Path
from app import app

client = TestClient(app)


def test_health_endpoint():
    """Test health check endpoint"""
    response = client.get("/health")
    
    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "healthy"
    assert "timestamp" in data
    assert "version" in data


def test_root_endpoint():
    """Test root endpoint"""
    response = client.get("/")
    
    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "ok"


def test_process_missing_file():
    """Test process endpoint without file"""
    response = client.post("/process")
    
    assert response.status_code == 422  # Unprocessable entity (missing file)


def test_process_invalid_levels():
    """Test process endpoint with invalid levels"""
    files = {"audio": ("test.m4a", b"fake audio data", "audio/m4a")}
    response = client.post("/process", files=files, data={"levels": "5,6,7"})
    
    assert response.status_code == 400  # Bad request


def test_cleanup_endpoint():
    """Test cleanup endpoint"""
    response = client.delete("/cleanup/test_job_123")
    
    # Should succeed even if files don't exist
    assert response.status_code in [200, 404]


if __name__ == '__main__':
    pytest.main([__file__, '-v'])

