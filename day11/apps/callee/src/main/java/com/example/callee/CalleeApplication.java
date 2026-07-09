package com.example.callee;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

// callee:Cloud Run 服务。网络层面其实是可路由的(ingress = ALL)，
// 不像 day09/10 那样靠安全组/prefix list 做网络隔离 —— GCP 这边的默认推荐
// 做法是 IAM 层面的隔离:没有 roles/run.invoker 权限的调用方，请求会在
// 到达容器之前就被 Cloud Run 拒绝(403)，容器代码完全不用关心鉴权。
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
        return "{\"from\":\"callee\",\"message\":\"Hello from the callee service — reached via Cloud Run IAM-authenticated call (roles/run.invoker), not network isolation!\"}";
    }
}
