// src/main/java/com/harness/springboothelloworld/HelloController.java
package com.harness.springboothelloworld;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;
import java.util.HashMap;
import java.util.Map;

@RestController
public class HelloController {

    @GetMapping("/api")
    public Map<String, Object> hello() {
        Map<String, Object> response = new HashMap<>();
        response.put("message", "Hello from Spring Boot Hello World!");
        response.put("timestamp", System.currentTimeMillis());
        response.put("pod", System.getenv().getOrDefault("POD_NAME", "unknown"));
        return response;
    }

    @GetMapping("/health")
    public Map<String, String> health() {
        Map<String, String> status = new HashMap<>();
        status.put("status", "UP");
        return status;
    }
}
