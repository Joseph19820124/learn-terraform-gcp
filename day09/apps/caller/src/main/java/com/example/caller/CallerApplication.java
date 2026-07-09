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

// caller:对外挂 ALB 的服务。/hello 会转身去调用 callee —— 用的地址就是
// ECS Service Connect 里 callee 声明的 client_alias 名字("callee")，
// 不是 IP、不是 Cloud Map 的全限定域名，就是这么个短名字，
// Service Connect 在 task 内部注入的代理会把它路由到真实的 callee task。
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
                + "/data via ECS Service Connect, got back: " + resp.body();
    }
}
