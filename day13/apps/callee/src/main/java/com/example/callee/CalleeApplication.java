package com.example.callee;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

// callee:也是一个公网可达的 App Runner 服务(is_publicly_accessible = true)。
// 和 day09-12 不同,这里没有任何网络层/身份层限制谁能调用它——App Runner
// 没有 Cloud Run 那种 roles/run.invoker,要做限制得靠 VPC Ingress
// Connection 或应用自己加认证,这天没实现,直接如实记录这个差距。
@SpringBootApplication
@RestController
public class CalleeApplication {

    public static void main(String[] args) {
        SpringApplication.run(CalleeApplication.class, args);
    }

    @GetMapping("/health")
    public String health() {
        return "OK";
    }

    @GetMapping("/data")
    public String data() {
        return "{\"from\":\"callee\",\"message\":\"Hello from the callee service — reached via AWS App Runner, no invoker-style auth needed (it doesn't have one)!\"}";
    }
}
