---
name: new-post
description: Create a new blog post markdown file in _posts with front matter ready. Use when the user wants to start a new post.
---

Create a new post file and stop. Do not write post content.

1. Get today's date (`date +%F`).
2. Create `_posts/<date>-new-post.md` (if it exists, add `-2`, `-3`, ...) with:

```markdown
---
layout: post
title: "제목"
title_en: "Title"
date: <date>
show_on_blog: true
---

<div class="ko" markdown="1">

여기에 글을 쓰세요.

</div>

<div class="en" markdown="1">

Write here.

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
```

3. Tell the user the file path. Remind them to rename the file slug and change both titles (`title` for Korean, `title_en` for English).
