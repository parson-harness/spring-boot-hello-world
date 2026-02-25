// src/main/java/com/harness/springboothelloworld/HelloController.java
package com.harness.springboothelloworld;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;
import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.net.HttpURLConnection;
import java.net.URL;
import java.util.HashMap;
import java.util.Map;

@RestController
public class HelloController {

    @Value("${app.version:1.0.0}")
    private String appVersion;

    @GetMapping("/api")
    public Map<String, Object> hello() {
        Map<String, Object> response = new HashMap<>();
        response.put("message", "Hello from Spring Boot Hello World!");
        response.put("timestamp", System.currentTimeMillis());
        response.put("pod", System.getenv().getOrDefault("POD_NAME", "unknown"));
        response.put("version", appVersion);
        response.put("instanceId", getInstanceId());
        return response;
    }

    private String getInstanceId() {
        try {
            URL url = new URL("http://169.254.169.254/latest/meta-data/instance-id");
            HttpURLConnection conn = (HttpURLConnection) url.openConnection();
            conn.setConnectTimeout(1000);
            conn.setReadTimeout(1000);
            BufferedReader reader = new BufferedReader(new InputStreamReader(conn.getInputStream()));
            String instanceId = reader.readLine();
            reader.close();
            return instanceId;
        } catch (Exception e) {
            return "unknown";
        }
    }

    @GetMapping("/health")
    public Map<String, String> health() {
        Map<String, String> status = new HashMap<>();
        status.put("status", "UP");
        return status;
    }
}
