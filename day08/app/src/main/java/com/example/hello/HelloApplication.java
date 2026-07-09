package com.example.hello;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

// 最小 Spring Boot app：一个 /health 给 ALB 健康检查用，
// 一个 /hello 给人看，端口 8080(和真实的 Nike 案例里 config.yml 的 container port 一致)。
@SpringBootApplication
@RestController
public class HelloApplication {

    public static void main(String[] args) {
        SpringApplication.run(HelloApplication.class, args);
    }

    @GetMapping("/health")
    public String health() {
        return "OK";
    }

    @GetMapping("/hello")
    public String hello() {
        return "Hello from ECS Fargate — deployed by Terraform, not Serverless Framework!";
    }
}
