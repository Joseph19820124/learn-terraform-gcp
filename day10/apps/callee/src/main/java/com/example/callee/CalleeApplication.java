package com.example.callee;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

// callee:纯内部服务，没有公网入口，只能被接入了同一个 VPC Lattice
// 服务网络的服务通过 Lattice 生成的 DNS 名字访问。
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
        return "{\"from\":\"callee\",\"message\":\"Hello from the callee service — reached via VPC Lattice, no public IP needed!\"}";
    }
}
