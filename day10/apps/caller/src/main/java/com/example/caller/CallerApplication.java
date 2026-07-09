package com.example.caller;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.time.Duration;

// caller:对外挂 ALB 的服务。/hello 会转身去调用 callee —— 用的地址是
// VPC Lattice 服务的 DNS 名字(*.vpc-lattice-svcs.<region>.on.aws)，
// 由 AWS 生成、通过环境变量 CALLEE_URL 注入。请求经过 Lattice 的监听器
// (默认 80 端口)转发到 callee 容器真实监听的端口。
@SpringBootApplication
@RestController
public class CallerApplication {

    private static final String CALLEE_URL =
            System.getenv().getOrDefault("CALLEE_URL", "http://callee:8080");

    private final HttpClient client = HttpClient.newBuilder()
            .connectTimeout(Duration.ofSeconds(3))
            .build();

    public static void main(String[] args) {
        SpringApplication.run(CallerApplication.class, args);
    }

    @GetMapping("/health")
    public String health() {
        return "OK";
    }

    @GetMapping("/hello")
    public String hello() throws Exception {
        HttpRequest req = HttpRequest.newBuilder()
                .uri(URI.create(CALLEE_URL + "/data"))
                .timeout(Duration.ofSeconds(3))
                .GET()
                .build();
        HttpResponse<String> resp = client.send(req, HttpResponse.BodyHandlers.ofString());
        return "Caller says hi! Called " + CALLEE_URL
                + "/data via VPC Lattice, got back: " + resp.body();
    }
}
