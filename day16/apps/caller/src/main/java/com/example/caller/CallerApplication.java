package com.example.caller;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.http.HttpStatusCode;
import org.springframework.http.client.JdkClientHttpRequestFactory;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.client.RestClient;

import java.net.http.HttpClient;
import java.time.Duration;

// caller:和 day09 完全一样的 Service Connect 调用逻辑,唯一的区别是这一天
// 加了真正的日志输出(day09-14 都没有——只是把内容拼进 HTTP 响应体返回,
// 容器的 stdout 其实什么都没打印过)。这些 log.info() 打到 stdout 后，
// 会被 FireLens(Fluent Bit sidecar,见 modules/ecs-fargate-service)拦截、
// 转发到 Loki，而不是走 day09 原来的 CloudWatch awslogs 驱动。
@SpringBootApplication
@RestController
public class CallerApplication {

    private static final Logger log = LoggerFactory.getLogger(CallerApplication.class);

    private static final String CALLEE_URL =
            System.getenv().getOrDefault("CALLEE_URL", "http://callee:8080");

    private final RestClient client;

    public CallerApplication() {
        JdkClientHttpRequestFactory factory = new JdkClientHttpRequestFactory(
                HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(3)).build());
        factory.setReadTimeout(Duration.ofSeconds(3));
        this.client = RestClient.builder().requestFactory(factory).build();
        log.info("Caller started, CALLEE_URL={}", CALLEE_URL);
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
        log.info("Received /hello request, calling callee at {}", CALLEE_URL);
        long start = System.currentTimeMillis();
        String body = client.get()
                .uri(CALLEE_URL + "/data")
                .retrieve()
                .onStatus(HttpStatusCode::isError, (req, res) -> {})
                .body(String.class);
        long elapsedMs = System.currentTimeMillis() - start;
        log.info("Callee responded in {}ms, body={}", elapsedMs, body);
        return "Caller says hi! Called " + CALLEE_URL
                + "/data via ECS Service Connect, got back: " + body;
    }
}
