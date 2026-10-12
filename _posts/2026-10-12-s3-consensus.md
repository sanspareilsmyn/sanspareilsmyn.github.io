---
layout: post
title: "S3는 합의를 대체하지 않았다."
title_en: "S3 Didn't Replace Consensus. It Changed How Often You Need It."
date: 2026-10-12
show_on_blog: true
---

<div class="ko" markdown="1">

### 1. 
최근 내가 흥미롭게 살펴 본 인프라 시스템들에는 묘한 공통점이 하나 있다.
- [WarpStream](https://www.warpstream.com/blog/kafka-is-dead-long-live-kafka): Kafka 프로토콜을 그대로 쓰지만, 브로커에 로컬 디스크가 없다. stateless agent가 받은 데이터를 곧바로 S3에 쓴다.
- [turbopuffer](https://turbopuffer.com/docs/architecture): 벡터 검색 엔진인데, 모든 쓰기는 S3에 WAL 파일 하나를 추가하는 것으로 끝난다.
- [SlateDB](https://slatedb.io/docs/design/overview/): 임베디드 KV 스토어인데, LSM tree의 데이터 파일과 DB 상태를 담은 manifest까지 전부 object storage에 둔다.  

저마다 분야는 다른데, 셋 다 ZooKeeper도, etcd도, 직접 운영하는 Raft 클러스터도 없다. 대신 달랑 S3 하나만 있다.
다시 말해서 데이터의 최종 기록은 S3에 있고, 각 노드는 그 데이터를 처리하거나 잠시 들고 있을 뿐이라는 뜻이다.
이렇게 S3를 새로운 consensus 계층으로 사용하는 이유가 무엇인지, 이러한 변화는 합리적인지에 대해 검토해보았다. **결론부터 말하면, "S3가 새로운 Consensus 계층이 되었다."는 말은 반만 맞다.** 하지만 나머지 반에 더 재미있는 함의들이 있다.

### 2. 
S3는 원래 coordination에 쓸 수 없는 저장소였다. 2020년 12월 이전에는 [strong read-after-write consistency](https://aws.amazon.com/about-aws/whats-new/2020/12/amazon-s3-now-delivers-strong-read-after-write-consistency-automatically-for-all-applications/)조차 보장하지 않았다. 방금 쓴 객체를 다시 읽어도 옛날 값이 나올 수 있었다는 뜻이다. 
이 문제는 2020년에 해결되었지만 여전히 결정적인 기능이 하나 빠져 있었다. **"이 파일이 없을 때만 써라"는 조건부 쓰기다.**

### 3. 
이게 왜 그렇게 중요한지는 테이블 포맷의 커밋 방식을 예를 들어 설명하면 바로 이해된다. [Delta Lake 프로토콜](https://www.databricks.com/blog/2019/08/21/diving-into-delta-lake-unpacking-the-transaction-log.html)에서 테이블의 변경 이력은 `_delta_log/00...00.json`처럼 버전 번호를 이름으로 가진 파일들이다. 다음 버전 파일을 만드는 것이 곧 커밋이다.  
그런데 Spark 클러스터 두 개가 동시에 테이블을 수정한다고 해 보자. 둘 다 현재 버전이 9라는 걸 확인하고, 둘 다 `...010.json`을 쓴다. 조건부 쓰기가 없으면 S3는 두 요청을 모두 성공시키고, 나중에 도착한 파일이 먼저 쓴 파일을 조용히 덮어쓴다. 어디에도 에러는 나지 않지만 한쪽의 커밋은 그대로 사라진다.
"먼저 확인하고 나서 쓰면 되지 않나?" 싶지만, **확인과 쓰기 사이에는 항상 틈이 있다.** 그래서 확인과 쓰기가 저장소 안에서 하나의 원자적 연산으로 일어나야 한다.  

### 4. 
그러니까 이건 "다음 버전을 누가 가져가는가?"를 여러 노드가 하나의 결정에 동의해야 하는 문제다. 다른 문제들을 보자. 리더 선출은 "이번 임기의 리더는 누구인가?", 분산 lock은 "지금 이 lock은 누구 것인가?"를 묻는다. 모양은 다르지만 이들은 모두 "여럿이 동시에 시도해도 정확히 하나만 이기고, 나머지는 자기가 졌다는 걸 안다"로 귀결된다. 
이걸 노드들끼리 메시지를 주고받으며 직접 정하려면 Raft 같은 합의 알고리즘이 필요하다. 그래서 보통은 이 판정을 대신해 줄 저장소를 심판으로 둔다. 예를 들어 [etcd의 transaction](https://etcd.io/docs/v3.5/learning/api/)은 "key의 버전이 내가 본 값과 같으면 쓰고, 아니면 실패"를 하나의 원자적 연산으로 한다.

### 5. 
그러니까 조율 도구의 핵심은 결국 "조건이 맞을 때만 쓰고, 아니면 실패를 알려 주는" 원자적 쓰기다. 문제는 S3에 바로 그게 없었다는 사실이다. S3의 PUT은 조건 없이 항상 성공했다. 
그래서 데이터는 S3에 두더라도 "누가 이겼는가"는 다른 곳에서 정해야 했다.

### 6. 
2024년, 마지막 퍼즐이 맞춰졌다.
- 2024년 8월: [`If-None-Match` 조건부 쓰기](https://aws.amazon.com/about-aws/whats-new/2024/08/amazon-s3-conditional-writes/). 같은 key의 객체가 없을 때만 쓰기가 성공한다.
- 2024년 11월: [`If-Match` 조건부 쓰기](https://aws.amazon.com/about-aws/whats-new/2024/11/amazon-s3-functionality-conditional-writes/). 객체의 ETag가 내가 알고 있는 값과 같을 때만 덮어쓴다.

이 기능에는 [추가 요금이 없다.](https://docs.aws.amazon.com/AmazonS3/latest/userguide/conditional-requests.html) 실패한 요청을 포함해 기존 요청 요금만 낸다.
기능 자체는 단순하다. 하지만 분산 시스템 관점에서 보면 의미가 크다. **key 하나에 대해 "내가 마지막으로 본 버전일 때만 바꿔라"라는 compare-and-swap(CAS)이 생긴 것이다.** 
실제로 [Gunnar Morling](https://www.morling.dev/blog/leader-election-with-s3-conditional-writes/)은 발표 직후 S3만으로 리더 선출을 구현했다. 
[SlateDB](https://github.com/slatedb/slatedb/blob/main/rfcs/0001-manifest.md)의 writer 교체도, Iceberg와 Delta의 커밋도 모양이 같다. 데이터는 덮어쓰지 않는 파일로 쓰고, 현재 상태를 가리키는 작은 파일 하나만 조건부로 바꾼다. **결국 S3 위의 합의는 작은 파일 하나를 누가 먼저 쓰느냐로 귀결된다.**

### 7. 
그런데 왜 하필 지금인가? 내가 생각하는 진짜 이유는 요금표에 있다. [AZ 간 데이터 전송](https://aws.amazon.com/ec2/pricing/on-demand/)은 GB당 각 방향 0.01달러이지만 [같은 리전의 S3에서 EC2로 가져오는 전송](https://aws.amazon.com/s3/pricing)은 무료이다.
Kafka는 데이터를 여러 AZ에 복제하기 때문에, 복제할 때마다 이 요금을 낸다. WarpStream은 처리량이 높은 Kafka 비용의 70~90%가 AZ 간 네트워크 요금이라고 주장했다. 
그러니까 S3가 이렇게 쓰이기 시작한 건 S3가 특별히 좋아서라기보다, **요금표가 디스크 복제를 비싸게 만들었기 때문**이다.   
물론 공짜는 없다. S3는 느리고, 요청마다 돈을 받는다. 그래서 S3 위의 시스템들은 하나같이 쓰기를 모아서 드물게 커밋한다. turbopuffer는 아예 namespace당 WAL 커밋을 1초에 1번으로 제한한다. **S3 위에서는 커밋을 얼마나 자주 하느냐가 곧 비용이다.**

### 8. 
하지만 자세히 보면 기존의 합의 계층은 완전히 사라지지 않았다.  

Kafka에서 쓰기 하나가 끝나려면 두 가지가 필요하다. 데이터를 안전하게 저장하는 일, 그리고 그 데이터가 파티션에서 몇 번째인지(offset) 정하는 일이다. 
기존 Kafka에서는 파티션 leader가 둘 다 한다. [WarpStream](https://www.warpstream.com/blog/kafka-is-dead-long-live-kafka)은 이 둘을 나눴다. 데이터는 S3에 쓰고, "파티션 안에서 batch들의 순서" 같은 정보는 자체 metadata store에 커밋한다. 두 단계가 모두 끝나야 producer에게 성공을 돌려준다. 그러니까 S3는 데이터를 담는 그릇일 뿐이고, 순서를 정하는 합의는 여전히 별도 시스템이 맡는다.  

Kafka의 diskless 논의도 방안은 다르지만 순서를 정하는 주체만 다를 뿐, 누구도 그 일을 S3에 맡기지 않았다. [Jack Vanlightly의 분석](https://jack-vanlightly.com/blog/2025/10/22/a-fork-in-the-road-deciding-kafkas-diskless-future)의 글을 읽어보면,
- KIP-1150 첫 번째 버전: 별도의 Batch Coordinator가 S3에 올라간 batch에 offset을 매긴다. WarpStream과 비슷한 구조다.
- KIP-1150 세 번째 버전: Batch Coordinator를 없애고, 기존 Kafka 파티션의 leader가 다시 순서를 정한다.
- KIP-1176: leader 기반 구조를 그대로 두고, 복제만 S3 위의 WAL로 바꾼다.  

S3의 CAS는 **드물고 굵직한 결정**에 쓰인다. 누가 지금 writer인가, 어떤 manifest가 최신인가 같은 결정이다. 반면 초당 수천 번 일어나는 메시지 순서 결정 같은 잦고 잘게 쪼개진 결정은 여전히 별도의 합의 계층이 맡는다.

### 9.
그래서 S3가 합의 계층을 대체했다기보다 **합의가 필요한 빈도를 줄이는 설계가 S3 덕분에 현실적인 선택지가 됐다**. 그러니까 설계할 때 던져야 할 질문도 바뀐다. 예전에는 "Raft 클러스터를 직접 운영할 것인가, ZooKeeper를 쓸 것인가"였다면, 이제는 "이 시스템은 얼마나 자주 합의가 필요한가"다.
- 1초에 한 번, 혹은 writer가 바뀔 때만 합의가 필요하다면: S3 CAS만으로 충분하다. 운영할 클러스터가 하나 줄어든다.
- 1초에 수천 번 순서를 정해야 한다면: 여전히 별도의 합의 계층이 필요하다. S3는 그 아래의 저장소일 뿐이다.

</div>

<div class="en" markdown="1">

### 1.

There is a curious common thread among the infrastructure systems I've been looking into recently.
- [WarpStream](https://www.warpstream.com/blog/kafka-is-dead-long-live-kafka): It speaks the Kafka protocol as-is, but its brokers have no local disks. Stateless agents write incoming data directly to S3.
- [turbopuffer](https://turbopuffer.com/docs/architecture): It's a vector search engine, yet every write boils down to appending a single WAL file to S3.
- [SlateDB](https://slatedb.io/docs/design/overview/): It's an embedded KV store, but it keeps everything in object storage, including the LSM tree's data files and the manifest that holds the database state.

They operate in different domains, but none of them has ZooKeeper, etcd, or a Raft cluster they operate themselves. Instead, all they have is S3. In other words, the final record of the data lives in S3, and each node merely processes that data or holds it temporarily. I've been looking into why S3 is being used as a new consensus layer, and whether this shift makes sense. **To get straight to the point, the claim that "S3 has become the new Consensus layer" is only half right.** But the other half has even more interesting implications.

### 2.

S3 was never a storage system you could use for coordination. Before December 2020, it didn't even guarantee [strong read-after-write consistency](https://aws.amazon.com/about-aws/whats-new/2020/12/amazon-s3-now-delivers-strong-read-after-write-consistency-automatically-for-all-applications/). In other words, you could write an object and immediately read it back, only to get the old value. That problem was solved in 2020, but one decisive capability was still missing. **Conditional writes: "Only write this if the file doesn't exist."**

### 3.

Why this matters becomes obvious if we look at how table formats commit changes. In the [Delta Lake protocol](https://www.databricks.com/blog/2019/08/21/diving-into-delta-lake-unpacking-the-transaction-log.html), a table's change history consists of files named after version numbers, such as `_delta_log/00...00.json`. Creating the next version's file is the commit.
Now imagine two Spark clusters modifying the same table at the same time. Both check that the current version is 9, and both write `...010.json`. Without conditional writes, S3 accepts both requests, and the file that arrives later silently overwrites the one written first. No error is raised, but one of the commits simply disappears. You might think, "Why not just check first and then write?" But **there is always a gap between checking and writing.** That's why the check and the write need to happen as a single atomic operation within the storage system itself.

### 4.
So this is fundamentally a problem of multiple nodes needing to agree on a single decision: "Who gets to claim the next version?" Consider other problems. Leader election asks, "Who is the leader for this term?" A distributed lock asks, "Who owns this lock right now?" They look different, but they all boil down to the same thing: "Even if multiple parties try at the same time, exactly one wins, and everyone else knows they lost." 
If nodes have to figure this out themselves by exchanging messages, you need a consensus algorithm like Raft. That's why we typically use a storage system as an arbiter to make the decision for us. For example, [etcd's transactions](https://etcd.io/docs/v3.5/learning/api/) perform "write if the key's version matches the value I observed; otherwise, fail" as a single atomic operation.

### 5.

So the essence of a coordination primitive is an atomic write that says, "Write only if the condition holds; otherwise, tell me it failed." The problem was that S3 lacked exactly this capability. An S3 PUT would always succeed, with no condition attached.  So even if you kept the data in S3, you had to decide somewhere else who had won.

### 6.

In 2024, the final piece of the puzzle fell into place.
- August 2024: [`If-None-Match` conditional writes](https://aws.amazon.com/about-aws/whats-new/2024/08/amazon-s3-conditional-writes/). A write succeeds only if no object exists under the same key.
- November 2024: [`If-Match` conditional writes](https://aws.amazon.com/about-aws/whats-new/2024/11/amazon-s3-functionality-conditional-writes/). An object can be overwritten only if its ETag matches the value I know.

These features come with [no additional charge](https://docs.aws.amazon.com/AmazonS3/latest/userguide/conditional-requests.html). You pay the usual request charges, including for failed requests. The features themselves are simple. But from a distributed systems perspective, they mean a lot. **S3 now gives you compare-and-swap (CAS) on a single key: "Change this only if it's still at the version I last saw."** In fact, [Gunnar Morling](https://www.morling.dev/blog/leader-election-with-s3-conditional-writes/) implemented leader election using nothing but S3 shortly after the feature was announced. 
Replacing a writer in [SlateDB](https://github.com/slatedb/slatedb/blob/main/rfcs/0001-manifest.md), as well as committing changes in Iceberg and Delta, follows the same pattern. Write data to immutable files, then conditionally update a single small file that points to the current state. **In the end, consensus on top of S3 boils down to who gets to write a single small file first.**

### 7.

But why now, of all times? I think the real reason is in the pricing tables. [Data transfer between Availability Zones](https://aws.amazon.com/ec2/pricing/on-demand/) costs $0.01 per GB in each direction, whereas [transferring data from S3 to EC2 in the same Region](https://aws.amazon.com/s3/pricing) is free. Kafka replicates data across multiple AZs, so you pay this fee every time data is replicated. WarpStream has claimed that cross-AZ networking accounts for 70–90% of Kafka's costs at high throughput. 
So S3 started being used this way not because S3 is particularly great, but because **the pricing model made disk replication expensive**.  
Of course, nothing is free. S3 is slow, and it charges you for every request. That's why systems built on S3 tend to batch writes and commit infrequently. turbopuffer even limits WAL commits to once per second per namespace. **On S3, how often you commit is directly a cost decision.**

### 8.

But if you look closely, the existing consensus layer hasn't disappeared entirely.

For a Kafka write to complete, two things need to happen: the data must be stored safely, and its position (offset) within the partition must be determined. In traditional Kafka, the partition leader does both. [WarpStream](https://www.warpstream.com/blog/kafka-is-dead-long-live-kafka) splits these responsibilities. It writes the data to S3 and commits metadata such as the ordering of batches within a partition to its own metadata store. Only after both steps are complete does it acknowledge success to the producer. In other words, S3 is merely the vessel that holds the data, while a separate system still handles consensus on ordering.  
The approaches discussed in Kafka's diskless proposals differ, but they only change who determines the order. None of them delegates that job to S3. Take a look at [Jack Vanlightly's analysis](https://jack-vanlightly.com/blog/2025/10/22/a-fork-in-the-road-deciding-kafkas-diskless-future):
- KIP-1150, first version: A separate Batch Coordinator assigns offsets to batches uploaded to S3. Structurally similar to WarpStream.
- KIP-1150, third version: The Batch Coordinator is removed, and the existing Kafka partition leader takes back responsibility for ordering.
- KIP-1176: The leader-based architecture stays intact, while replication is replaced with a WAL on S3.

S3's CAS is used for **infrequent, coarse-grained decisions**: who the current writer is, which manifest is the latest, and so on. Frequent, fine-grained decisions, such as determining message order thousands of times per second, are still handled by a separate consensus layer.

### 9.
So rather than saying S3 has replaced the consensus layer, **I'd say S3 has made it practical to design systems that need consensus less frequently.** That changes the question we should ask when designing a system. It used to be, "Should we operate our own Raft cluster or use ZooKeeper?" Now it's, "How often does this system actually need consensus?"
- If you only need consensus once per second, or when the writer changes: S3 CAS may be enough. That's one less cluster to operate.
- If you need to determine ordering thousands of times per second: You still need a separate consensus layer. S3 is just the storage underneath it.

</div>

<!-- 이미지 예시
<figure style="text-align: center;">
    <img
        class="about-photo"
        src="{{ '../assets/images/파일명.jpeg' | relative_url }}"
        alt="설명"
        style="display: block; margin: 0 auto;"
    >
    <figcaption style="text-align: center; color: #888; font-size: 0.85em; margin-top: 8px;">
        캡션
    </figcaption>
</figure>
-->
