---
layout: post
title: "자율주행 데이터의 진짜 문제는 크기가 아니다"
title_en: "The Real Problem with AV Data Isn't Size"
date: 2026-10-05
show_on_blog: true
---

<div class="ko" markdown="1">

1. 자율주행 데이터를 다룰 때 가장 어려운 지점은 크기가 아니다. 나도 직접 데이터를 다루어보기 전까지는 차 한 대가 하루에 만들어 내는 몇 TB의 양에 압도되곤 했다. 
이렇게 크고 많은 차량 데이터를 수집하다 보면, 얼마나 효율적으로 데이터를 저장하고 불러와야 하는지에 대한 고민에 매몰되기 쉽다. 아닌 게 아니라, 실제로 데이터는 매우 크다. 
- Motional이 2019년 공개한 nuScenes 데이터셋의 카메라 스펙은 1600x900 해상도, 12Hz, 차량 당 6대이다. 
- 압축 전 이미지 한 장은 대략 1600 × 900 × 3바이트 = 4.3MB. 카메라 6대 합계가 초당 약 311MB, 시간당 약 1.1TB. 라이더와 레이더는 뺀 카메라만의 숫자다.

2. 하지만 크기는 이미 답이 알려진 문제이기 때문에, 오히려 다루기 쉬운 문제라고 생각한다. 오브젝트 스토리지, 압축, 분산 처리 도구는 이미 충분히 성숙해서 사용성이 훌륭하다.
그러니까 크기는 "어떻게 해야 하지?"가 아니라 "얼마나 쓸 거지?"의 문제이다. **하지만 아래 세 가지 문제는 돈을 더 쓴다고 자동으로 해결되지 않는다.**

3. 문제 1: 시간  
일반적으로 데이터 엔지니어링에서는, 서로 다른 데이터를 묶을 때 그것을 식별할 수 있는 기준이 있다. 웹 서비스에서는 `user_id`, 로그 분석에서는 `request_id`나 `trace_id`와 같은 식이다.
그런데 자율주행 데이터에서는 시간이 제일 중요하다. 같은 순간에 카메라, 라이더, 레이더가 본 것을 하나의 사건으로 묶어야 한다. 
웹 서비스에서 사용자의 이벤트가 몇 초 차이 난다고 해서 서로 다른 사용자가 되는 것은 아니지만, 자율주행에서는 **몇 밀리초의 차이**도 두 센서가 서로 다른 세계를 바라보고 있다는 의미가 될 수 있다.  
문제는 센서들이 같은 시계로 같은 주기에 데이터를 만들지 않는다는 사실이다. 센서가 늘어날 수록 시계는 더욱 늘어난다. 예를 들어, 자동차가 시속 100km로 달린다고 하자. 이 차는 1초에 약 28m를 이동한다. 10ms의 시간 차이만 있어도 물체 위치가 28cm 달라진다는 의미이다. 
일반적으로 데이터베이스를 다룰 때 생각하는, "가장 가까운 timestamp로 join하면 되겠지"라는 접근이 통하지 않는 이유이다.

4. 문제 2: 희귀성  
주행 데이터의 대부분은 지루하다. 정말 필요한 건 드물게 일어나는 incident이다. 갑작스러운 끼어들기, 공사 구간, 무단횡단, 도로 위 낯선 물체 등과 같은 것들이다.
그리고 이러한 데이터는 매우 희귀하다. [이 연구](https://www.rand.org/pubs/research_reports/RR1478.html)에 따르면, 사고/사망이 주행 거리에 비해 너무 드물기 때문에 자율주행차의 안정성을 통계적으로 증명하려면 **몇십~몇백 년**을 달려야 한다고 말하고 있다.
데이터를 더 모으는 것이 전부가 아니라, 희귀한 데이터를 잘 찾는 게 더 중요하다. 경쟁력은 여기에서 나온다. 

5. 문제 3: 재현성  
로그는 보통 한 번 집계되면 역할이 끝난다. 하지만 주행 로그는 그 특성상 몇 번이고 다시 쓰인다. 원본 위에는 새로운 메타데이터가 계속 추가된다. 그래서 언제든 "이 모델은 어떤 데이터, 어떤 라벨 버전으로 학습했는가?"에 대한 명확한 답변이 가능해야 한다.
자율주행에서 데이터 자체만이 아니라 데이터 버전에 대한 관리가 너무나도 중요한 이유이다.

6. 그래서 자율주행 데이터 엔지니어링의 핵심은 결국 데이터의 양을 관리하는 것이 아니라 데이터의 의미를 보존하는 것에 가깝다고 나는 생각했다. 
다음 글들은, 이러한 문제들을 다루기 위해 어떤 작업들이 이루어졌고 어떤 작업들이 필요한지에 대해 회사 내부의 정보를 노출하지 않는 선에서 생각 정리를 해 보려고 한다.


</div>

<div class="en" markdown="1">

1. The hardest part of working with autonomous driving data is not its size. Before I worked with it myself, I used to be overwhelmed by the several terabytes a single car produces in a day.
When you collect this much vehicle data, it's easy to get stuck thinking only about how to store and load it efficiently. And to be fair, the data really is huge.
- The nuScenes dataset, released by Motional in 2019, uses six cameras per car, each at 1600x900 resolution and 12Hz.
- One uncompressed image is about 1600 × 900 × 3 bytes = 4.3MB. All six cameras together come to about 311MB per second, or about 1.1TB per hour. And that's cameras only, without lidar and radar.

2. But I think size is actually the easier problem, because we already know the answer. Object storage, compression, and distributed processing tools are mature and easy to use.
So size isn't a question of "how do we do this?" but of "how much will we spend?" **The three problems below, though, don't go away just because you spend more money.**

3. Problem 1: Time  
In most data engineering, there's a key you use to join different pieces of data. In web services it's `user_id`; in log analysis it's `request_id` or `trace_id`.
In autonomous driving, the most important key is time. What the cameras, lidar, and radar saw at the same moment has to be tied together as one event.
In a web service, a user's events being a few seconds apart doesn't turn them into different users. In autonomous driving, even **a few milliseconds** can mean two sensors are looking at different worlds.  
The problem is that sensors don't produce data on the same clock or at the same rate. The more sensors you add, the more clocks you have. Say a car is driving at 100km/h. It moves about 28m per second. A time gap of just 10ms means an object's position is off by 28cm.
This is why the usual database approach of "just join on the nearest timestamp" doesn't work.

4. Problem 2: Rarity  
Most driving data is boring. What you really need are the rare incidents: sudden cut-ins, construction zones, jaywalkers, strange objects on the road.
And this kind of data is very rare. [This study](https://www.rand.org/pubs/research_reports/RR1478.html) says that because crashes and deaths are so rare relative to miles driven, proving an autonomous car is safe statistically would take **tens to hundreds of years** of driving.
Collecting more data isn't everything. Finding the rare data well matters more, and that's where the competitive edge comes from.

5. Problem 3: Reproducibility  
Most logs have done their job once they're aggregated. Driving logs, by nature, get used again and again. New metadata keeps getting added on top of the raw data. So at any time, you need a clear answer to "Which data, and which label version, was this model trained on?"
That's why, in autonomous driving, managing data versions matters just as much as managing the data itself.

6. So I came to think that the core of autonomous driving data engineering is less about managing the amount of data and more about preserving what the data means.
In the next posts, I'll share my thoughts on what has been done and what still needs to be done to deal with these problems, without revealing any internal company information.

</div>

