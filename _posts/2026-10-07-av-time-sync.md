---
layout: post
title: "자율주행 데이터에서 시간은 어떻게 맞춰지는가?"
title_en: "How Is Time Synchronized in Autonomous Driving Data?"
date: 2026-10-07
show_on_blog: true
---

<div class="ko" markdown="1">

자율주행 센서 데이터의 가장 큰 어려움 중 하나는 시간이다.
1. 문제 1: 시계가 서로 다르다.  
자율주행차 안에는 여러 대의 컴퓨터가 들어간다. 카메라, 라이다, 레이더 같은 센서가 데이터를 만들고 컴퓨터가 그 데이터를 받아 처리한다. 물론 센서 자체에도 데이터 전처리나 통신을 위한 프로세서가 들어갈 수 있다.
NVIDIA의 [Hyperion 10](https://www.nvidia.com/en-us/solutions/autonomous-vehicles/in-vehicle-computing) 문서를 보면, 2개의 DRIVE AGX Thor 기반 컴퓨트, 14개의 카메라, 9개의 라이더, 1개의 라이다, 12개의 초음파 센서가 서로 통신하고 있다. 각 장치가 자신의 시계를 가지고 있는 것이다.  
이전 글에서 설명했듯, 자율주행에서는 몇 밀리초의 차이도 의미 있는 물체의 위치 변화를 만들어내기 때문에 더 정밀한 시간 동기화가 필요하다. 
대표적인 방법으로 [PTP](https://en.wikipedia.org/wiki/Precision_Time_Protocol)가 있는데, Waymo가 공개한 [특허](https://patents.google.com/patent/US20220206444A1/en)를 보면 이에 대한 구체적인 설명이 있다.
이들은 PTP를 이용해 차량 내 여러 시계를 하나의 기준에 동기화하고, GNSS(GPS의 상위 개념)을 통해 얻은 절대적 시간을 기준으로 사용해서 내부 시간을 100ns 수준까지 동기화한다. 만약 터널과 같은 이슈로 외부 신호가 끊기면 내부 시계로 주행하다가 사후 동기화하는 매커니즘도 구현되어 있다.

2. 문제 2: 시계가 같아도, 찍는 순간이 다르다.  
그런데 시계를 맞추는 것만이 문제가 아니다. 모든 시계가 완벽하게 맞았다고 해도 문제는 남는다. 센서마다 데이터를 만드는 주기가 다르기 때문이다.
[nuScenes](https://arxiv.org/abs/1903.11027) 기준으로 카메라는 12Hz, 라이다는 20Hz, 레이더는 13Hz로 동작한다.  
그래서 데이터셋을 만드는 쪽에서는 촬영 순간 자체를 맞추려고 한다. nuScenes는 회전하는 라이다가 각 카메라 시야의 중앙을 지나는 순간에 그 카메라의 셔터를 누르게 했다. 사후에 타임스탬프를 보고 가장 가까운 데이터를 골라내는 것이 아니라, 애초에 하드웨어 단계에서 같은 장면을 보도록 촬영 순간을 맞춘 것이다.

3. 문제 3: 한 프레임 안에서도 시간이 흐른다.  
이건 기존의 직관에 반하는 아주 흥미로운 문제이다. 우리는 보통 "프레임 하나 = 한 순간"이라고 생각하지만, 실제로는 그렇지 않다. 
라이다는 한 바퀴를 도는 동안 점을 찍는다. 만약 라이다가 10Hz로 동작한다면 한 바퀴에 0.1초가 걸린다.
만약 차가 시속 100km로 이동한다면 0.1초 동안 약 2.8m를 이동하기 때문에 라이다 프레임의 처음과 끝 점은 약 2.8m 떨어진 위치에서 찍힌 셈이다.  
카메라도 마찬가지다. Waymo 데이터셋의 카메라는 rolling shutter 방식을 사용하기 때문에 이미지의 모든 픽셀이 같은 순간에 촬영되지 않는다. 위쪽 줄을 찍고 아래쪽 줄을 찍는 사이에도 시간이 흐른다. 그래서 [Waymo](https://waymo.com/intl/fil/open/data/perception)는 이미지마다 rolling shutter timing 정보를 함께 제공하고, 이를 고려해 라이다 점을 카메라 이미지에 투영한 결과도 별도로 제공한다.  
결국 정확한 시간의 단위는 상황에 따라 프레임보다 더 작아진다. 어떤 경우에는 센서 프레임 하나의 타임스탬프로 충분하지만, 어떤 경우에는 라이다의 **점 하나**, 카메라의 **줄 하나**가 언제 취득되었는지까지 알아야 한다.

4. 이렇게까지 해도 오차는 0이 되지 않는다. [Waymo](https://openaccess.thecvf.com/content_CVPR_2020/papers/Sun_Scalability_in_Perception_for_Autonomous_Driving_Waymo_Open_Dataset_CVPR_2020_paper.pdf)가 공개한 카메라와 라이다 사이의 동기화 에러는 99.7% 신뢰 수준에서 -6ms에서 7ms 사이이다.
아까 했던 시속 100km의 차량을 기준으로 다시 계산해보면 약 20cm의 차이인 것이다.

5. 데이터 엔지니어링을 하는 사람의 입장에서 중요한 것은, 저장된 timestamp가 **얼마나 믿을 만한지**이다.
- 먼저 timestamp가 실제로 무엇을 가리키는지 알아야 한다. 예를 들어 카메라와 라이다의 timestamp가 둘 다 `10.000초`라고 하자. 
그렇다고 두 센서가 정확히 같은 순간을 보고 있었다는 뜻은 아니다. 카메라의 `10.000초`는 사진의 노출을 시작한 순간일 수 있고, 라이다의 `10.000초`는 한 바퀴의 측정을 끝낸 순간일 수 있다.
- 센서 데이터를 실제로 join할 때도 세부 사항들이 있다. 예를 들어 카메라 timestamp가 `10.000s`이고 라이다 timestamp가 `10.004s`라면 4ms 차이니까 같은 장면이라고 볼 수 있을 수 있다. 하지만 단순히 "가장 가까운 timestamp를 찾는다"로 끝내면 안 된다. 어떤 시간 차이까지 같은 순간으로 볼 것인지 temporal tolerance를 명시해야 한다.
    ```text
    camera:  10.000 s
    lidar:   10.004 s   → match
    radar:   10.021 s   → reject
    ```
- 센서의 주기 자체도 검증할 수 있다. 12Hz 센서라면 이상적으로 frame 간격이 약 83ms여야 한다. 갑자기 200ms가 됐다면 단순히 데이터가 늦게 들어온 것인지, 프레임이 실제로 유실된 것인지, 시계에 문제가 생긴 것인지 확인해야 한다.

6. 시간 동기화가 중요한 이유는 시간이 틀어진 데이터가 반드시 에러를 내는 것은 아니기 때문이다. 이는 데이터 파이프라인의 실패가 아니라 모델 성능의 조용한 저하로 나타날 수 있다.
</div>

<div class="en" markdown="1">
One of the biggest challenges in autonomous driving sensor data is time.

1. Problem 1: The clocks are different.  
   An autonomous vehicle contains multiple computers. Cameras, LiDARs, and radars generate data, and computers receive and process that data. Sensors themselves can also contain processors for data preprocessing or communication.
   According to NVIDIA's [Hyperion 10](https://www.nvidia.com/en-us/solutions/autonomous-vehicles/in-vehicle-computing) documentation, the system consists of two DRIVE AGX Thor-based compute systems, 14 cameras, 9 radars, 1 LiDAR, and 12 ultrasonic sensors communicating with each other. Each device has its own clock.  
   As I explained in the previous post, even a difference of a few milliseconds can translate into a meaningful change in an object's perceived position in autonomous driving, so more precise time synchronization is necessary.
   One common approach is [PTP](https://en.wikipedia.org/wiki/Precision_Time_Protocol). Waymo's [patent](https://patents.google.com/patent/US20220206444A1/en) provides a concrete example of how this can be implemented.
   They use PTP to synchronize multiple clocks inside the vehicle to a common reference, using the absolute time obtained through GNSS (a broader term that includes GPS) as the reference, and synchronize the internal clocks down to around 100ns. If the external signal is lost, such as when entering a tunnel, the system can continue operating using its internal clocks and synchronize again once the external signal becomes available.
2. Problem 2: Even if the clocks are synchronized, the capture times are different.  
   But synchronizing the clocks is not the only problem. Even if all the clocks were perfectly synchronized, another problem remains: different sensors operate at different frequencies.
   According to [nuScenes](https://arxiv.org/abs/1903.11027), cameras operate at 12Hz, LiDAR at 20Hz, and radar at 13Hz.  
   So dataset creators also try to synchronize the actual moments at which sensors capture data. In nuScenes, the camera shutter is triggered when the rotating LiDAR passes through the center of the camera's field of view. Rather than matching the closest timestamps after the fact, they synchronize the actual capture moments at the hardware level so that the sensors are looking at the same scene at roughly the same time.
3. Problem 3: Time passes even within a single frame.  
   This is a particularly interesting problem because it goes against our usual intuition. We tend to think of "one frame = one moment," but in reality, that is not always true.
   A LiDAR captures points as it rotates. If a LiDAR operates at 10Hz, one full rotation takes 0.1 seconds.
   If the vehicle is traveling at 100 km/h, it moves about 2.8m during those 0.1 seconds. This means that the first and last points in a LiDAR frame were captured from positions roughly 2.8m apart.
   Cameras have a similar issue. The cameras in the Waymo dataset use a rolling shutter, so not all pixels in an image are captured at exactly the same moment. Time passes between capturing the rows at the top and the rows at the bottom of the image. That's why [Waymo](https://waymo.com/intl/fil/open/data/perception) provides rolling shutter timing information for each image, and also provides LiDAR-to-camera projections that take this timing into account.  
   Ultimately, the appropriate unit of time can be smaller than a frame. In some cases, a single timestamp for an entire sensor frame is sufficient, but in others, we need to know when an individual LiDAR point or image row was captured.
4. Even after all of this, the error is not zero. [Waymo](https://openaccess.thecvf.com/content_CVPR_2020/papers/Sun_Scalability_in_Perception_for_Autonomous_Driving_Waymo_Open_Dataset_CVPR_2020_paper.pdf) reports that the synchronization error between the camera and LiDAR is between -6ms and 7ms at a 99.7% confidence level.
   Using the same example of a vehicle traveling at 100 km/h, that translates to roughly 20cm of positional difference.
5. From a data engineering perspective, what matters is how much we can trust the stored timestamp.
- First, we need to understand what a timestamp actually represents. For example, suppose the timestamps from a camera and a LiDAR are both 10.000s. That does not necessarily mean that the two sensors were looking at the exact same moment. The camera's 10.000s might represent the moment its exposure started, while the LiDAR's 10.000s might represent the moment its full scan was completed.
- There are also details to consider when actually joining sensor data. For example, if the camera timestamp is 10.000s and the LiDAR timestamp is 10.004s, we might consider them to represent the same scene because they are only 4ms apart. But we cannot simply find the "closest timestamp" and call it done. We need to explicitly define how large a time difference we are willing to accept as representing the same moment.
  ```text
  camera:  10.000 s
  lidar:   10.004 s   → match
  radar:   10.021 s   → reject
  ```
- We can also validate the sensor's sampling period itself. If a 12Hz sensor should ideally produce a frame roughly every 83ms, but the interval suddenly becomes 200ms, we need to determine whether the data was simply delayed, a frame was actually dropped, or there was a problem with the clock.
6. The reason time synchronization matters is that incorrectly timed data does not necessarily produce an error. This may not appear as a failure in the data pipeline, but rather as a quiet degradation in model performance.

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
