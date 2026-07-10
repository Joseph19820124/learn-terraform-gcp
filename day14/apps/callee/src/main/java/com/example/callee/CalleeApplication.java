package com.example.callee;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

// callee:也是一个公网可达的 ECS Express Mode 服务(默认公网子网 →
// internet-facing ALB)。和 day13 一样,这里没有任何网络层/身份层限制
// 谁能调用它——虽然 Express Mode 理论上支持私有子网 → internal ALB,
// 这一天为了和 day13 对等没有实现,如实记录这个"能做但没做"的差距。
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
        return "{\"from\":\"callee\",\"message\":\"Hello from the callee service — reached via ECS Express Mode, still no invoker-style auth (same gap as App Runner)!\"}";
    }
}
