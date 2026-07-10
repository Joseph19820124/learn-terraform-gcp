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

// caller:AWS App Runner 服务。/hello 会转身去调用 callee —— 用的地址是
// App Runner 分配的默认域名(https://xxx.<region>.awsapprunner.com)，
// 通过环境变量 CALLEE_URL 注入。
//
// 关键点:这一天两个服务都是公网可达的(is_publicly_accessible = true)。
// App Runner 不像 Cloud Run 那样有原生的 IAM invoker 概念，也不像
// ECS Service Connect/VPC Lattice 那样默认给你一套安全组隔离——它的
// callee 访问限制只能靠 VPC Ingress Connection(把服务收进特定 VPC，
// 需要额外配置 VPC Endpoint)或者应用层自己加认证，这一天为了控制复杂度
// 没有实现，直接留白记录在 README 里。
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
                + "/data via AWS App Runner, got back: " + body;
    }
}
