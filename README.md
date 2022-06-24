# CyberAcademy
GLR Cybersecurity Academy 2022 Systems Track
This activity is for teen-aged cadets in Civil Air Patrol who wish to advance their cybersecurity knowledge. Put on by a group of volunteers, the Great Lakes Region Cybersecurity Academy hosts three learning tracks: Networking, IOT/OT, and Systems. The systems track focuses on hardening activities to lockdown or secure individual systems. This academy is considered an advanced level activity where cadets from around the nation come together at Ferris State University for a week to learn more in-depth curriculum and have fun with other like-minded teens.

The systems track is being re-designed this year to create a realistic scenario of a local business neededing help hardening their local IT systems. The intended outcomes of this track are for students to leave with the knowledge and technical skills to imediately add value upon landing an entry level IT or junior consulting role.

## Scenario

Mr. Robot’s Computer Repair Shop has requested the services of Allsafe Cybersecurity to harden their store’s on-premise infrastructure. They have setup a typical small business network containing a domain controller, a file and print server, and two Windows 10 clients. However, they lack the expertise to properly secure, or harden, their devices according to today’s best practices.

Students will play the role of Jr. Cybersecurity Engineers employed by Allsafe Cybersecurity. Senior Engineers have made an exact replica of Mr. Robot’s infrastructure in a lab environment. Cadets will spend their week building out a report for Mr. Robot’s Computer Repair Shop detailing hardening recommendations based on the replicated lab environment. At the end of the week, they will present their report to the client for an approval to implement their hardening steps. Upon approval, the client will give the engineers a maintenance window to perform their hardening steps.

![mr_robot_topology.png](https://github.com/lbunge/CyberAcademy/blob/main/images/mr_robot_topology.png)

## Technical Implementation Overview

Each student will have access to their own individual lab environment consisting of the Mr. Robot Network Topology. These environments will be physically hosted within Azure utilizing virtual machines and separated via IP addresses. For example, student 1 will be assigned the IP range 192.168.101.x where student 2 will be assigned 192.168.102.x. Thus, each student will operate out of an independent /24 network range.

The lab will be reachable through any latest browser via Apache Guacamole. Each student will be given unique credentials so they can login to Guacamole and only see their assigned lab environment. This will also allow students to work in their lab whether they are in the classroom or in their room during the evening through their own computer.

This training environment will be built via automation so it is repeatable year after year for consistent growth. This automation will only bring the environment up to a pre-hardened baseline. There should then be pre-made scripts and automation efforts to complete all harden activities that cadets will learn throughout the week. All scripts, automation efforts, checklists, and documentation will be stored in GitHub for version control.

![logical_topology.png](https://github.com/lbunge/CyberAcademy/blob/main/images/logical_topology.png)
