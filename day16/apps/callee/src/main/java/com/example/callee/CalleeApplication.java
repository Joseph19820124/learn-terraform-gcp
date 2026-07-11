package com.example.callee;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

// callee:纯内部服务，没有公网入口，只能被同一个 ECS Service Connect
// 命名空间里的服务通过内部名字 "callee" 访问。和 caller 一样，这一天加了
// 真正的日志输出，经 FireLens sidecar 转发到 Loki。
@SpringBootApplication
@RestController
public class CalleeApplication {

    private static final Logger log = LoggerFactory.getLogger(CalleeApplication.class);

    public static void main(String[] args) {
        SpringApplication.run(CalleeApplication.class, args);
    }

    @GetMapping("/health")
    public String health() {
        return "OK";
    }

    @GetMapping("/data")
    public String data() {
        log.info("Received /data request");
        String body = "{\"from\":\"callee\",\"message\":\"Hello from the callee service — reached via ECS Service Connect, no public IP needed!\"}";
        log.info("Returning response: {}", body);
        return body;
    }
}
