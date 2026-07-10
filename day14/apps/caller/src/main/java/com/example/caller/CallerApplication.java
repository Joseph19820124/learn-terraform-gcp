package com.example.caller;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.http.HttpStatusCode;
import org.springframework.http.client.JdkClientHttpRequestFactory;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.client.RestClient;

import java.net.http.HttpClient;
import java.time.Duration;

// caller:ECS Express Mode 服务。/hello 会转身去调用 callee —— 用的地址是
// Express Mode 自动分配的默认域名(https://xxx.ecs.<region>.on.aws)，
// 通过环境变量 CALLEE_URL 注入。
//
// 关键点:和 day13(App Runner)一样，这一天两个服务也都是公网可达的
// (用的默认公网子网，走 internet-facing ALB)。AWS 官方文档确认 Express
// Mode 支持用私有子网换来 internal ALB(从而让 callee 网络不可达)，但
// 那需要额外建私有子网 + NAT 网关，这一天为了和 day13 保持对等范围没有
// 实现，作为已知可选项写进 README。
@SpringBootApplication
@RestController
public class CallerApplication {

    private static final String CALLEE_URL =
            System.getenv().getOrDefault("CALLEE_URL", "http://callee:8080");

    private final RestClient client;

    public CallerApplication() {
        JdkClientHttpRequestFactory factory = new JdkClientHttpRequestFactory(
                HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(3)).build());
        factory.setReadTimeout(Duration.ofSeconds(3));
        this.client = RestClient.builder().requestFactory(factory).build();
    }

    public static void main(String[] args) {
        SpringApplication.run(CallerApplication.class, args);
    }

    @GetMapping("/health")
    public String health() {
        return "OK";
    }

    @GetMapping("/hello")
    public String hello() {
        String body = client.get()
                .uri(CALLEE_URL + "/data")
                .retrieve()
                .onStatus(HttpStatusCode::isError, (req, res) -> {})
                .body(String.class);
        return "Caller says hi! Called " + CALLEE_URL
                + "/data via ECS Express Mode, got back: " + body;
    }
}
